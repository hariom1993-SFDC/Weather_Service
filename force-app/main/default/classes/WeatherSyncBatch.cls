/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : WeatherSyncBatch
 * Author          : Hariom Bajpai
 * Created Date    : Oct 21, 2026
 * Last Modified By: Hariom Bajpai
 * Last Modified On: Oct 21, 2026
 * Description     : This class is doing the asynchronous, high-volume refresh: as a Batch it processes all
 *                   Locations in chunks of 50 (each chunk with its own governor limits, so it scales to any
 *                   number of records), and as a Schedulable it runs itself every hour so weather stays up to
 *                   date without anyone clicking.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public without sharing class WeatherSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    public static final Integer BATCH_SIZE = 50;
    public static final String JOB_NAME = 'Weather Sync - Hourly';
    public static final String HOURLY = '0 0 * * * ?';

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            [SELECT Id FROM Location__c]
        );
    }

    public void execute(Database.BatchableContext context, List<Location__c> scope) {
        Map<Id, String> errors = WeatherService.refresh(new List<Id>(new Map<Id, Location__c>(scope).keySet()));
        if (!errors.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'Weather sync failed for ' + errors.size() + ' location(s): ' + errors);
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'Weather sync finished.');
    }

    public void execute(SchedulableContext context) {
        run();
    }

    public static Id run() {
        return Database.executeBatch(new WeatherSyncBatch(), BATCH_SIZE);
    }

    public static String scheduleHourly() {
        return System.schedule(JOB_NAME, HOURLY, new WeatherSyncBatch());
    }
}