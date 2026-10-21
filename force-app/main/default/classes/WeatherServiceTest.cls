/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : WeatherServiceTest
 * Author          : Hariom Bajpai
 * Created Date    : Oct 21, 2026
 * Last Modified By: Hariom Bajpai
 * Last Modified On: Oct 21, 2026
 * Description     : This class is doing the testing of WeatherService and WeatherController across 15 scenarios:
 *                   correct field mapping, no duplicate rows, coordinate and city-name lookup, every error type
 *                   (401, 404, 429, 500, bad JSON, missing data, timeout, invalid coordinates, deleted location),
 *                   the 100-callout limit, and errors being sent to the UI.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
private class WeatherServiceTest {
    @TestSetup
    static void setup() {
        insert new Location__c(Name = 'London', Latitude__c = 51.5074, Longitude__c = -0.1278);
    }

    private static Id londonId() {
        return [SELECT Id FROM Location__c LIMIT 1].Id;
    }

    @IsTest
    static void refresh_success_savesAllFields() {
        WeatherCalloutMock mock = new WeatherCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<Id, String> errors = WeatherService.refresh(new List<Id>{ londonId() });
        Test.stopTest();

        Assert.isTrue(errors.isEmpty(), 'No errors expected: ' + errors);
        WeatherInfo__c w = WeatherService.getLatest(londonId());
        Assert.areEqual(15.53, w.Temperature__c, 'Rounded to 2 decimals');
        Assert.areEqual(15.12, w.Feels_Like__c);
        Assert.areEqual(14.2, w.Temp_Min__c);
        Assert.areEqual(16.8, w.Temp_Max__c);
        Assert.areEqual('light rain', w.Description__c);
        Assert.areEqual('10d', w.Icon__c);
        Assert.areEqual('London', w.City_Name__c);
        Assert.isNotNull(w.Fetched_At__c);

        String endpoint = mock.lastRequest.getEndpoint();
        Assert.isTrue(
            endpoint.startsWith('callout:WeatherAPIExternalCredential/data/2.5/weather?lat=51.5074&lon=-0.1278'),
            endpoint
        );
        Assert.isFalse(endpoint.contains('appid'), 'API key must never be in the URL');
        Assert.areEqual('GET', mock.lastRequest.getMethod());
    }

    @IsTest
    static void refresh_existingWeather_isUpdatedNotDuplicated() {
        insert new WeatherInfo__c(Location__c = londonId(), Temperature__c = 1);
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());

        Test.startTest(); 
        WeatherService.refresh(new List<Id>{ londonId() });
        Test.stopTest();

        List<WeatherInfo__c> rows = [SELECT Temperature__c FROM WeatherInfo__c];
        Assert.areEqual(1, rows.size(), 'Existing row must be updated, not duplicated');
        Assert.areEqual(15.53, rows[0].Temperature__c);
    }

    @IsTest
    static void error_invalidApiKey_401() {
        assertError(new WeatherCalloutMock(401, '{"cod":401}'), 'API key');
    }

    @IsTest
    static void error_rateLimit_429() {
        assertError(new WeatherCalloutMock(429, '{}'), 'rate limit');
    }

    @IsTest
    static void error_serverError_500() {
        assertError(new WeatherCalloutMock(500, '{}'), 'HTTP 500');
    }

    @IsTest
    static void error_badJson() {
        assertError(new WeatherCalloutMock(200, '{not json'), 'Could not read');
    }

    @IsTest
    static void error_noTemperatureData() {
        assertError(new WeatherCalloutMock(200, '{"name":"x"}'), 'temperature');
    }

    @IsTest
    static void error_networkTimeout() {
        assertError(new WeatherCalloutMock.Timeout(), 'Could not reach');
    }

    @IsTest
    static void cityOnly_usesLocationNameAsCity() {
        Location__c city = new Location__c(Name = 'New York');
        insert city;
        WeatherCalloutMock mock = new WeatherCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<Id, String> errors = WeatherService.refresh(new List<Id>{ city.Id });
        Test.stopTest();

        Assert.isTrue(errors.isEmpty(), 'No errors expected: ' + errors);
        String endpoint = mock.lastRequest.getEndpoint();
        Assert.isTrue(endpoint.contains('?q=New+York&units=metric'), endpoint);
        Assert.isFalse(endpoint.contains('lat='), endpoint);
        Assert.areEqual(1, [SELECT COUNT() FROM WeatherInfo__c WHERE Location__c = :city.Id]);
    }

    @IsTest
    static void error_cityNotFound_404() {
        assertError(new WeatherCalloutMock(404, '{"cod":"404","message":"city not found"}'), 'could not find');
    }

    @IsTest
    static void invalidCoordinates_failWithoutCallout() {
        WeatherCalloutMock mock = new WeatherCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);
        List<WeatherInfo__c> rows = new List<WeatherInfo__c>();

        String outOfRange = WeatherService.fetch(
            new Location__c(Name = 'X', Latitude__c = 91, Longitude__c = 0),
            null,
            rows,
            System.now()
        );
        String nothingToSearch = WeatherService.fetch(new Location__c(Name = ' '), null, rows, System.now());

        Assert.isTrue(outOfRange.contains('Latitude'), outOfRange);
        Assert.isTrue(nothingToSearch.contains('city name'), nothingToSearch);
        Assert.areEqual(0, mock.callCount, 'No callout when there is nothing valid to search');
        Assert.isTrue(rows.isEmpty());
    }

    @IsTest
    static void deletedLocation_reportsNotFound() {
        Id locId = londonId();
        delete [SELECT Id FROM Location__c];
        Map<Id, String> errors = WeatherService.refresh(new List<Id>{ locId });
        Assert.isTrue(errors.get(locId).contains('not found'));
        Assert.isTrue(WeatherService.refresh(null).isEmpty());
        Assert.isNull(WeatherService.getLatest(null));
    }

    @IsTest
    static void bulk_over100_respectsCalloutLimit() {
        List<Location__c> more = new List<Location__c>();
        for (Integer i = 0; i < 100; i++) {
            more.add(new Location__c(Name = 'L' + i, Latitude__c = 10, Longitude__c = 10));
        }
        insert more; 
        List<Id> ids = new List<Id>(new Map<Id, Location__c>([SELECT Id FROM Location__c]).keySet());
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());

        Test.startTest();
        Map<Id, String> errors = WeatherService.refresh(ids);
        Test.stopTest();

        Assert.areEqual(100, [SELECT COUNT() FROM WeatherInfo__c], '100 = callout limit');
        Assert.areEqual(1, errors.size(), 'The extra location is skipped, not crashed');
    }

    @IsTest
    static void controller_returnsAndRefreshesWeather() {
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());
        Assert.isNull(WeatherController.getLatestWeather(londonId()), 'Nothing stored yet');

        Test.startTest();
        WeatherInfo__c w = WeatherController.refreshWeather(londonId());
        Test.stopTest();

        Assert.areEqual('light rain', w.Description__c);
        Assert.areEqual(15.53, WeatherController.getLatestWeather(londonId()).Temperature__c);
    }

    @IsTest
    static void controller_sendsErrorMessageToUi() {
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock(401, '{}'));
        try {
            WeatherController.refreshWeather(londonId());
            Assert.fail('Expected the error to be sent to the UI');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('API key'), e.getMessage());
        }
    }

    private static void assertError(HttpCalloutMock mock, String expected) {
        Test.setMock(HttpCalloutMock.class, mock);
        Id locId = londonId();
        Map<Id, String> errors = WeatherService.refresh(new List<Id>{ locId });
        Assert.isTrue(errors.get(locId).containsIgnoreCase(expected), 'Got: ' + errors.get(locId));
        Assert.areEqual(0, [SELECT COUNT() FROM WeatherInfo__c], 'Nothing saved on failure');
    }
}