/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : WeatherService
 * Author          : Hariom Bajpai
 * Created Date    : Oct 21, 2026
 * Last Modified By: Oct 21, 2026
 * Last Modified On: Oct 21, 2026
 * Description     : This class is doing the core work: for each Location it calls OpenWeatherMap through the 
 					Named Credential (using Latitude/Longitude, or the Location Name as the city when coordinates are blank),
					turns every problem (401, 404, 429, timeout, bad JSON) into a readable message instead of throwing, and 
					saves the result in WeatherInfo__c with one bulk upsert so each location keeps a single weather row that 
					is updated, never duplicated.
 */
public inherited sharing class WeatherService {
    @TestVisible
    private static final String ENDPOINT = 'callout:WeatherAPIExternalCredential/data/2.5/weather';
    private static final Integer TIMEOUT_MS = 20000;

    public static Map<Id, String> refresh(List<Id> locationIds) {
        Map<Id, String> errors = new Map<Id, String>();
        if (locationIds == null || locationIds.isEmpty()) {
            return errors;
        }
        Map<Id, Location__c> locations = new Map<Id, Location__c>(
            [SELECT Id, Name, Latitude__c, Longitude__c FROM Location__c WHERE Id IN :locationIds]
        );

        Map<Id, Id> existingWeatherIds = new Map<Id, Id>();
        for (WeatherInfo__c row : [
            SELECT Id, Location__c
            FROM WeatherInfo__c
            WHERE Location__c IN :locations.keySet()
        ]) {
            existingWeatherIds.put(row.Location__c, row.Id);
        }

        List<WeatherInfo__c> weatherRows = new List<WeatherInfo__c>();
        List<Id> rowLocationIds = new List<Id>(); 
        Datetime fetchedAt = System.now();

        for (Id locationId : locationIds) {
            Location__c location = locations.get(locationId);
            String error;
            if (location == null) {
                error = 'Location not found or you do not have access to it.';
            } else if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                error = 'Callout limit reached; this location will be updated by the next sync.';
            } else {
                error = fetch(location, existingWeatherIds.get(locationId), weatherRows, fetchedAt);
            }
            if (error == null) {
                rowLocationIds.add(locationId);
            } else {
                errors.put(locationId, error);
            }
        }

        List<Database.UpsertResult> results = Database.upsert(weatherRows, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                errors.put(rowLocationIds[i], results[i].getErrors()[0].getMessage());
            }
        }
        return errors;
    }

    public static WeatherInfo__c getLatest(Id locationId) {
        if (locationId == null) {
            return null;
        }
        List<WeatherInfo__c> rows = [
            SELECT Id, Temperature__c, Feels_Like__c, Temp_Min__c, Temp_Max__c, Description__c, Icon__c,
                City_Name__c, Fetched_At__c
            FROM WeatherInfo__c
            WHERE Location__c = :locationId
            WITH USER_MODE
            ORDER BY Fetched_At__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @TestVisible
    private static String fetch(
        Location__c location,
        Id existingWeatherId,
        List<WeatherInfo__c> weatherRows,
        Datetime fetchedAt
    ) {
        String query;
        Decimal lat = location.Latitude__c;
        Decimal lon = location.Longitude__c;
        if (lat != null && lon != null) {
            if (Math.abs(lat) > 90 || Math.abs(lon) > 180) {
                return 'Latitude must be between -90 and 90 and Longitude between -180 and 180.';
            }
            query = 'lat=' + lat.toPlainString() + '&lon=' + lon.toPlainString();
        } else if (String.isNotBlank(location.Name)) {
            query = 'q=' + EncodingUtil.urlEncode(location.Name.trim(), 'UTF-8');
        } else {
            return 'Enter Latitude and Longitude, or a city name as the Location Name.';
        }

        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT + '?' + query + '&units=metric');
        request.setMethod('GET');
        request.setTimeout(TIMEOUT_MS);

        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException e) {
            return 'Could not reach the weather service: ' + e.getMessage();
        }

        Integer status = response.getStatusCode();
        if (status == 401) {
            return 'Weather service rejected the API key (401). Check the External Credential "WeatherAPIExternalCredential".';
        }
        if (status == 404) {
            return 'The weather service could not find this location (404). Check the city name or coordinates.';
        }
        if (status == 429) {
            return 'Weather service rate limit reached (429). Please try again later.';
        }
        if (status != 200) {
            return 'Weather service error (HTTP ' + status + ').';
        }

        WeatherResponse parsed;
        try {
            parsed = (WeatherResponse) JSON.deserialize(response.getBody(), WeatherResponse.class);
        } catch (Exception e) {
            return 'Could not read the weather service response.';
        }
        if (parsed == null || parsed.main == null) {
            return 'Weather service response did not contain temperature data.';
        }

        weatherRows.add(toRecord(location.Id, existingWeatherId, parsed, fetchedAt));
        return null;
    }

    private static WeatherInfo__c toRecord(Id locationId, Id existingWeatherId, WeatherResponse r, Datetime fetchedAt) {
        WeatherInfo__c info = new WeatherInfo__c(
            Temperature__c = round(r.main.temp),
            Feels_Like__c = round(r.main.feels_like),
            Temp_Min__c = round(r.main.temp_min),
            Temp_Max__c = round(r.main.temp_max),
            City_Name__c = r.name?.left(100),
            Fetched_At__c = fetchedAt
        );
        if (existingWeatherId != null) {
            info.Id = existingWeatherId; 
        } else {
            info.Location__c = locationId; 
        }
        if (r.weather != null && !r.weather.isEmpty()) {
            info.Description__c = r.weather[0].description?.left(255);
            info.Icon__c = r.weather[0].icon?.left(10);
        }
        return info;
    }

    private static Decimal round(Decimal value) {
        return value?.setScale(2, System.RoundingMode.HALF_UP);
    }

    public class WeatherResponse {
        public List<Condition> weather;
        public MainData main;
        public String name;
    }

    public class Condition {
        public String description;
        public String icon;
    }

    public class MainData {
        public Decimal temp;
        public Decimal feels_like;
        public Decimal temp_min;
        public Decimal temp_max;
    }
}