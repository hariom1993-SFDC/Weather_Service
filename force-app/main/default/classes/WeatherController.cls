public with sharing class WeatherController {
    @AuraEnabled(cacheable=true)
    public static WeatherInfo__c getLatestWeather(Id locationId) {
        return WeatherService.getLatest(locationId);
    }


    @AuraEnabled
    public static WeatherInfo__c refreshWeather(Id locationId) {
        String error = WeatherService.refresh(new List<Id>{ locationId }).get(locationId);
        if (error != null) {
            AuraHandledException toUi = new AuraHandledException(error);
            toUi.setMessage(error);
            throw toUi;
        }
        return WeatherService.getLatest(locationId);
    }
}