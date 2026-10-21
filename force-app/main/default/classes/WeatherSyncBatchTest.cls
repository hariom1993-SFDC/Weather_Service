/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : WeatherSyncBatchTest
 * Author          : Hariom Bajpai
 * Created Date    : Oct 21, 2026
 * Last Modified By: Hariom Bajpai
 * Last Modified On: Oct 21, 2026
 * Description     : This class is doing the testing of the asynchronous part: the batch refreshes every location,
 *                   failures do not stop the job, the hourly schedule is created correctly, and the scheduled run
 *                   starts the batch.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
private class WeatherSyncBatchTest {
    @TestSetup
    static void setup() {
        List<Location__c> locations = new List<Location__c>();
        for (Integer i = 0; i < 3; i++) {
            locations.add(new Location__c(Name = 'City ' + i, Latitude__c = 51.5, Longitude__c = -0.12));
        }
        insert locations;
    }

    @IsTest
    static void batch_refreshesEveryLocation() {
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());

        Test.startTest();
        WeatherSyncBatch.run();
        Test.stopTest();

        Assert.areEqual(3, [SELECT COUNT() FROM WeatherInfo__c], 'One weather row per location');
    }

    @IsTest
    static void batch_failures_doNotStopTheJob() {
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock(500, '{}'));

        Test.startTest();
        WeatherSyncBatch.run();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM WeatherInfo__c], 'Nothing saved, but no crash');
        Assert.areEqual(
            'Completed',
            [SELECT Status FROM AsyncApexJob WHERE ApexClass.Name = 'WeatherSyncBatch' LIMIT 1].Status
        );
    }

    @IsTest
    static void scheduleHourly_createsJob() {
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());
        Test.startTest();
        String jobId = WeatherSyncBatch.scheduleHourly();
        Test.stopTest();

        Assert.areEqual(
            WeatherSyncBatch.HOURLY,
            [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId].CronExpression
        );
    }

    @IsTest
    static void scheduledRun_startsBatch() {
        Test.setMock(HttpCalloutMock.class, new WeatherCalloutMock());

        Test.startTest();
        new WeatherSyncBatch().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.areEqual(3, [SELECT COUNT() FROM WeatherInfo__c]);
    }
}