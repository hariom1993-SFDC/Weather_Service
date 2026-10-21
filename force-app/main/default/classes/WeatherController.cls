/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : WeatherController
 * Author          : Hariom Bajpai
 * Created Date    : Oct 21, 2026
 * Last Modified By: Hariom Bajpai
 * Last Modified On: Oct 21, 2026
 * Description     : This class is doing the bridge between the weatherDisplay LWC and Apex: getLatestWeather
 *                   loads the stored weather for the record page (cacheable), and refreshWeather runs when
 *                   "Get Weather Details" is clicked, fetching fresh weather and sending any error message
 *                   straight to the screen.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
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