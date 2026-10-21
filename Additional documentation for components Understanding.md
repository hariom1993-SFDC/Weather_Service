# What each part of the app does

This is a walk-through of every piece I built for the Weather Forecast app and the job each one does. I've left out the test classes; the README covers those.

---

## The Apex classes

### WeatherService

This is the heart of the app. Whenever weather needs to be fetched, whether it's one person clicking a button or the hourly job refreshing everything, it ends up here. I kept all the logic in this one class so there's only one place to look and one place to fix things.

It starts by taking the list of Locations it's been asked to refresh and reading them from the database in one go. Straight after that, it checks whether any of those Locations already has a Weather Info record. That's what stops duplicates. If weather already exists, it gets updated instead of a new record being created.

Next it works out how to search for each Location. If both Latitude and Longitude are filled in, it uses those, because coordinates are exact. If they're empty, it treats the Location's Name as a city, so a Location called "Mumbai,IN" just works. If there's nothing usable at all (no coordinates and no name), or the coordinates are out of range, it doesn't bother calling the API. It simply comes back with a message explaining what's missing.

Then it calls OpenWeatherMap. The request goes through the Named Credential, asks for temperatures in Celsius, and waits up to 20 seconds. The code never touches the API key. Salesforce adds it to the request behind the scenes, which is exactly what I wanted from a security point of view.

When the answer comes back, it checks what happened. If everything's fine, it picks out the temperature, the "feels like" value, the min and max, a short description, the icon and the city name, rounds the numbers neatly, and stamps the time it fetched them. If something went wrong, it never crashes. A wrong API key, a city it can't find, too many requests, a server problem, a dropped connection or a reply it can't make sense of all get turned into a plain sentence that a normal user can understand.

One thing Salesforce is strict about is that you can't call an outside service after you've already saved something in the same transaction. So the class makes all its calls first, and only once they're all done does it save every Weather Info record together in a single step. It also keeps an eye on Salesforce's limit of 100 outside calls per transaction. If it's ever asked to do more than that, the extras are politely skipped with a note that the next sync will pick them up.

At the end, it hands back a list of anything that failed, with the reason for each. If a Location isn't on that list, it was saved fine. Importantly, one bad Location never spoils it for the others.

It also has a small helper that simply returns the saved weather for one Location, so the page has something to show. It only returns what the current user is allowed to see.

---

### WeatherController

This class is the go-between for the weather card on the page and the Apex behind it. The card never talks to anything else, which keeps things tidy.

It does two things. When someone opens a Location, it quietly fetches whatever weather is already saved so the card can show it straight away. This part is cached, so the page feels quick.

When someone clicks **Get Weather Details**, it asks WeatherService to refresh just that Location. If it works, the fresh weather goes straight back to the card. If it doesn't, the class passes the actual reason up to the screen, so the user sees something useful like "could not find this location" instead of a vague "something went wrong".

It also respects the user's access, so nobody can refresh a Location they aren't allowed to see.

---

### WeatherSyncBatch

This is the part that keeps everything fresh in the background, and it's how the app copes with a large number of Locations.

It works through every Location in small groups of 50. Salesforce treats each group as its own separate piece of work with its own limits, so whether you have ten Locations or a hundred thousand, it behaves the same way and never runs out of room. For each group, it simply hands the Locations to WeatherService to do the real work.

If a few Locations fail along the way, say someone typed a city name wrong, the job notes it in the log and carries on. It doesn't stop halfway, and it still finishes normally.

The same class can also schedule itself to run every hour, under the name "Weather Sync - Hourly". Once that's set up, nobody has to remember to click anything. The weather just stays current.

I chose groups of 50 because it sits comfortably below Salesforce's limit of 100 calls, and it doesn't hammer OpenWeatherMap's free plan. The job runs with full visibility of all Locations, because a background job that only refreshed some of them wouldn't be much use.

---

## The weather card (ShowWeatherLWC)

This is the **Current Weather** card that sits on every Location page. I built it with Salesforce's own design system, so it feels like a natural part of Salesforce rather than something bolted on. It's made of four files, each with its own job.

### ShowWeatherLWC.html: what you see

This file is the layout of the card. At the top is the title "Current Weather" with the **Get Weather Details** button in the corner. When weather is available, there's a soft blue panel with the weather icon, the temperature in big friendly numbers, a short description like "Light Rain", and the city name. Underneath are three small tiles for Feels Like, Min and Max, and below those a line saying when it was last updated.

It also covers the in-between moments. While something is loading, a spinner appears. If something goes wrong, a red box shows the message. If no weather has been fetched yet, there's a gentle note suggesting you click the button.

### ShowWeatherLWC.js: how it behaves

This file is what makes the card come alive. As soon as the page opens, it loads any weather that's already saved. When you click the button, it greys the button out so you can't click it twice by accident, asks for fresh weather, updates the card, and pops up a green "Weather updated" message.

If anything goes wrong, it takes whatever error came back, turns it into one clear sentence, shows it in the red box, and also shows a red pop-up message. It also handles the small presentation details:

- rounding temperatures and adding °C
- turning "light rain" into "Light Rain"
- showing a dash when a value is missing
- building the link to the right weather icon

### ShowWeatherLWC.css: how it looks

This file adds a few finishing touches on top of the standard Salesforce styling: the soft blue background behind the main panel, the large light-weight temperature text, a fixed size for the weather icon, and rounded corners on the tiles. Nothing fancy, just enough to make it pleasant to look at.

### ShowWeatherLWC.js-meta.xml: where it's allowed

This is the component's settings file. It makes the card show up in Lightning App Builder under the name ShowWeatherLWC, and it only lets you place it on Location pages, so nobody can drop it somewhere it wouldn't work.

---

## The objects

### Location

This is where you save each place you want weather for. The **Name** is the label for the place, and if you don't fill in any coordinates, it doubles as the city to search for. Adding the country code, like "London,GB", helps when a city name exists in more than one country. **Latitude** and **Longitude** are optional. If you have them, fill them in and they'll be used instead of the name, because they're more precise.

There's also a validation rule called **Valid_Coordinates** to stop mistakes. You can leave both coordinates empty or fill in both, but not just one, and they have to be real values: Latitude between -90 and 90, Longitude between -180 and 180. If something's off, it tells you clearly what to fix.

### Weather Info

This holds the current weather for a Location. Each Location only ever has one, and it simply gets updated every time the weather is refreshed, so the data doesn't keep piling up.

It's linked to its Location with a master-detail relationship. That means weather can't exist on its own, it follows the same access as its Location, and if a Location is deleted, its weather goes with it.

It stores:

- the temperature, what it feels like, and the current minimum and maximum, all in Celsius
- a short description such as "clear sky"
- the code for the weather icon
- the city name OpenWeatherMap matched (handy for checking it found the right place)
- the time Salesforce fetched it

---

## Security and access

### Named Credential (WeatherAPIExternalCredential)

This stores the address of the OpenWeatherMap API and tells Salesforce that calling it is allowed. The code only ever uses this name, never a hard-coded web address. A nice side effect is that no separate Remote Site Setting is needed.

### External Credential (WeatherAPIExternalCredential)

This is where the API key lives, safely encrypted inside Salesforce. The key is stored on the principal **WeatherAPIPrincipallCredential**, and a custom header called **x-api-key** slips it into each request at the very last moment. Because of this, the key never appears in the code, in a web address, in the logs or on GitHub.

### Permission set (Weather App User)

This gives people exactly what they need to use the app and nothing more. They can create and manage Locations, and they can see Weather Info but not change it, since only the system should write weather data. It also lets them use the controller behind the weather card and gives them access to the API key through the External Credential. Anyone without this permission set simply can't use the weather feature.

### Trusted URL (OpenWeatherMap_Icons)

The weather pictures come from openweathermap.org, and Salesforce won't show images from outside websites unless you allow them. This setting does exactly that. Without it, everything would still work; you just wouldn't see the little weather icon.

---

## The app and the page

### Weather Forecast app

This is the app you open from the App Launcher. It keeps everything to do with weather in one place, and it's where the Locations tab lives.

### Locations tab

This is where you see all your Locations and add new ones, either by typing a city name or by entering coordinates.

### Location record page

This is the page that opens when you click on a Location. I added the weather card to it in Lightning App Builder and set it as the default, so everyone sees the Current Weather card on every Location without any extra setup.
