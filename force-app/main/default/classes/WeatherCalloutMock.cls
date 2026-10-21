/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : WeatherCalloutMock
 * Author          : Hariom Bajpai
 * Created Date    : Oct 21, 2026
 * Last Modified By: Hariom Bajpai
 * Last Modified On: Oct 21, 2026
 * Description     : This class is doing the job of a fake OpenWeatherMap for unit tests, returning a realistic
 *                   London reply or any error status (or a network timeout) so tests can check every scenario
 *                   without calling the real internet.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
 @IsTest
public class WeatherCalloutMock implements HttpCalloutMock {
    public static final String LONDON =
        '{"weather":[{"main":"Rain","description":"light rain","icon":"10d"}],' +
        '"main":{"temp":15.534,"feels_like":15.12,"temp_min":14.2,"temp_max":16.8},' +
        '"name":"London","cod":200}';

    private final Integer statusCode;
    private final String body;
    public Integer callCount = 0;
    public HttpRequest lastRequest;

    public WeatherCalloutMock() {
        this(200, LONDON);
    }

    public WeatherCalloutMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
        callCount++;
        lastRequest = request;
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setBody(body);
        return response;
    }

    public class Timeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Read timed out');
        }
    }
}