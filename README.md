# Weather Forecast for Salesforce

Hi! This is a small Salesforce app I built that shows live weather for any place you save in Salesforce. It gets the data from the OpenWeatherMap API, saves it on the record, and shows it in a clean card on the page.

The idea is simple: you create a **Location**, open it, click **Get Weather Details**, and you see the current weather. You don't need to know the coordinates. A city name is enough.

---

## What it looks like

In my org there's an app called **Weather Forecast** with a **Locations** tab.

When you create a new Location you have two options:

- **Just type a city.** Put the city in the Name field, for example _Mumbai,IN_ or _London,GB_, and leave Latitude and Longitude empty. Adding the country code helps when the same city name exists in more than one country.
- **Or give exact coordinates.** Fill in Latitude and Longitude, for example 51.5074 and -0.1278. In this case the Name can be anything you like, such as "Head Office", because the coordinates are used instead.

Open the record and you'll see a **Current Weather** card with the temperature, a weather icon, a short description like "Light Rain", the city name, three small tiles for _Feels Like_, _Min_ and _Max_, and the time it was last updated. Click **Get Weather Details** whenever you want fresh numbers.

If something goes wrong, like a misspelled city or a bad API key, the card tells you in plain words instead of showing a technical error.

---

## How it works

When you click the button, the page asks Salesforce for fresh weather. Salesforce calls OpenWeatherMap, either with your coordinates or with the city name, and saves the answer on the Location. The card then shows it straight away.

There's also a background job that refreshes the weather for every Location once an hour, so the data stays up to date even if nobody clicks anything.

Here's what each piece does:

- **WeatherService** does the real work. For each Location it decides whether to search by coordinates or by city name, calls OpenWeatherMap, turns any problem into a friendly message, and saves the result. Each Location keeps just one weather record, which gets updated every time, so the data never piles up.
- **WeatherController** sits between the page and the service. It loads the saved weather when the page opens and fetches new weather when you click the button.
- **WeatherSyncBatch** is the background job. It goes through all Locations in groups of 50 and runs every hour, so it copes fine even with thousands of records.
- **showWeatherLWC** is the weather card you see on the page, built with Salesforce's own design style (SLDS).
- **WeatherCalloutMock**, **WeatherServiceTest** and **WeatherSyncBatchTest** are the tests. The mock pretends to be OpenWeatherMap so the tests never call the real internet.

### The two objects

**Location** holds the place: a Name (used as the city when there are no coordinates), plus optional Latitude and Longitude. A validation rule makes sure you either fill in both coordinates or neither, and that they're in a valid range.

**Weather Info** holds the weather for that place: temperature, feels like, min, max, description, icon, city name and the time it was fetched. It's linked to Location as a master-detail, so weather can't exist on its own and is removed automatically if the Location is deleted.

### Why I built it this way

- **The API key is never in the code.** It's stored safely inside Salesforce (in an External Credential), and Salesforce adds it to each request for me through a Named Credential. It isn't in the code or in this repository, and only users with the right permission set can use it.
- **One weather record per Location.** Before saving, the code checks whether a Location already has weather and updates it instead of creating a new one.
- **Calls first, saves after.** Salesforce doesn't allow calling an outside service after saving data in the same step, so the code makes all the calls first and then saves everything together. It also stays within Salesforce's limit of 100 calls at a time.
- **Errors never crash anything.** A bad key, an unknown city, too many requests, a slow connection or a strange response all become a readable message. If one Location fails, the others are still updated.
- **Ready for lots of records.** The background job works in small groups, and each group gets its own fresh Salesforce limits, so it handles a few Locations or many thousands the same way.

---

## Setting it up

### What you need

- A Salesforce org (a free Developer Edition is fine)
- VS Code with the Salesforce Extension Pack
- A free OpenWeatherMap API key (new keys can take up to a couple of hours to start working)

### Step 1 – Deploy the code

Open this project in VS Code and connect it to your org (Command Palette → _SFDX: Authorize an Org_). Then right-click the **force-app** folder and choose **SFDX: Deploy This Source to Org**.

### Step 2 – Add your API key

The key is a secret, so it's added in Setup rather than deployed.

First create the **External Credential**. In Setup, open _Named Credentials_, go to the _External Credentials_ tab and click **New**:

1. Name it **WeatherAPIExternalCredential** and choose **Custom** as the authentication protocol.
2. Add a principal called **WeatherAPIPrincipallCredential** (Named Principal), with one authentication parameter named **ApiKey** whose value is your OpenWeatherMap key.
3. Add a custom header named **x-api-key** with the value _{!$Credential.WeatherAPIExternalCredential.ApiKey}_

Then create the **Named Credential**. Go to the _Named Credentials_ tab and click **New**:

1. Name it **WeatherAPIExternalCredential**.
2. Set the URL to *https://api.openweathermap.org* and pick the External Credential you just made.
3. Tick **Enabled for Callouts** and **Allow Formulas in HTTP Header**, then save.

### Step 3 – Put the weather card on the page

Open any Location record, click the gear icon and choose **Edit Page**. Drag **showWeatherLWC** onto the page, save, and activate it as the org default.

If you don't have the Weather Forecast app or the Locations tab yet, create them in Setup under _Tabs_ and _App Manager_.

---

## Testing it

### Automated tests

There are 19 tests. To run them, go to Setup → _Apex Test Execution_ → **Select Tests**, choose **WeatherServiceTest** and **WeatherSyncBatchTest**, and click **Run**. They should all pass.

The tests check that:

- every field is saved correctly, without duplicates
- searching works both by coordinates and by city name
- every kind of failure is handled: bad key, unknown city, too many requests, server error, broken response, slow connection, invalid coordinates, deleted Location
- more than 100 Locations at once doesn't break anything
- the background job and the hourly schedule work

All tests use the fake OpenWeatherMap, so no real calls are made.

### Trying it in the app

These are the checks I do by hand:

1. Create a Location called _Mumbai,IN_ with no coordinates and click **Get Weather Details**. Mumbai's weather appears with a green "Weather updated" message.
2. Create one called _Test Coords_ with Latitude 51.5074 and Longitude -0.1278. You get London's weather, because the coordinates win over the name.
3. Click the button again on the same record. The numbers and time update, and there's still only one Weather Info record.
4. Create one called _Xyzabc_ with no coordinates. The card shows a red message saying the location couldn't be found.
5. Try saving a Location with only Latitude filled in. The validation rule stops you.
6. Change the API key to "abc" and click the button. You get a clear "rejected the API key" message. Put the real key back afterwards.

### The background job

To refresh all Locations at once:

1. Open the **Developer Console** → _Debug_ → _Open Execute Anonymous Window_.
2. Type _WeatherSyncBatch.run();_ and click **Execute**.

To make it run every hour, do the same with _WeatherSyncBatch.scheduleHourly();_

You can check it in Setup:

- **Apex Jobs** shows the job as Completed.
- **Scheduled Jobs** shows "Weather Sync - Hourly".

### Postman

If you like testing APIs directly, import the collection from the **postman** folder. The first part calls OpenWeatherMap on its own. The second part creates a Location in Salesforce, runs the background job and reads back the saved weather. Step-by-step notes are in the **docs** folder.

---

## If something isn't working

- **"rejected the API key"**: check the key on the principal and the x-api-key header, and make sure _Allow Formulas in HTTP Header_ is ticked on the Named Credential.
- **"We couldn't access the credential(s)"**: the permission set doesn't include the principal, or it isn't assigned to you.
- **"could not find this location"**: check the spelling, add the country code (like _London,GB_), or use coordinates instead.
- **"rate limit reached"**: the free OpenWeatherMap plan allows about 60 calls a minute. Wait a moment and try again.
- **No weather icon**: in Setup → _Trusted URLs_, make sure **OpenWeatherMap_Icons** (for https://openweathermap.org) is active.

---

Thanks for taking a look!
