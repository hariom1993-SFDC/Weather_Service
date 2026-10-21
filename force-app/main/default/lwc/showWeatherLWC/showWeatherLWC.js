/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Component Name  : weatherDisplay
 * Author          : Hariom Bajpai
 * Created Date    : Oct 21, 2026
 * Last Modified By: Hariom Bajpai
 * Last Modified On: Oct 21, 2026
 * Description     : This component is doing the display logic on the Location record page: it loads the stored
 *                   weather with @wire, runs the "Get Weather Details" button to fetch fresh data through
 *                   WeatherController, formats temperature, description, city and Feels Like / Min / Max values,
 *                   and shows loading, empty and error states with success or error toasts.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLatestWeather from '@salesforce/apex/WeatherController.getLatestWeather';
import refreshWeather from '@salesforce/apex/WeatherController.refreshWeather';

const ICON_BASE_URL = 'https://openweathermap.org/img/wn/';
const EMPTY = '—';

function reduceError(error) {
    if (!error) {
        return 'Unknown error';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    if (typeof error.message === 'string') {
        return error.message;
    }
    return 'Unknown error';
}

function formatNumber(value, suffix = '') {
    if (value === null || value === undefined) {
        return EMPTY;
    }
    return `${Math.round(Number(value) * 10) / 10}${suffix}`;
}

export default class ShowWeatherLWC extends LightningElement {
    @api recordId;

    weather;
    error;
    isLoading = true;
    isRefreshing = false;
    wiredWeatherResult;

    @wire(getLatestWeather, { locationId: '$recordId' })
    wiredWeather(result) {
        this.wiredWeatherResult = result;
        const { data, error } = result;
        if (data !== undefined) {
            this.weather = data; 
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.weather = undefined;
            this.error = reduceError(error);
            this.isLoading = false;
        }
    }

    async handleRefresh() {
        if (!this.recordId || this.isRefreshing) {
            return;
        }
        this.isRefreshing = true;
        this.error = undefined;
        try {
            this.weather = await refreshWeather({ locationId: this.recordId });
            await refreshApex(this.wiredWeatherResult); // keep the @wire cache in sync
            this.toast('Weather updated', 'Latest weather fetched from OpenWeatherMap.', 'success');
        } catch (e) {
            this.error = reduceError(e);
            this.toast('Could not fetch weather', this.error, 'error');
        } finally {
            this.isRefreshing = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get isBusy() {
        return this.isLoading || this.isRefreshing;
    }

    get hasWeather() {
        return !!this.weather;
    }

    get showEmptyState() {
        return !this.isLoading && !this.weather && !this.error;
    }

    get iconUrl() {
        return this.weather?.Icon__c ? `${ICON_BASE_URL}${this.weather.Icon__c}@2x.png` : null;
    }

    get temperatureLabel() {
        return formatNumber(this.weather?.Temperature__c, '°C');
    }

    get descriptionLabel() {
        const text = this.weather?.Description__c || '';
        return text.replace(/\b\w/g, (c) => c.toUpperCase());
    }

    get cityLabel() {
        return this.weather?.City_Name__c || EMPTY;
    }

    get stats() {
        const w = this.weather || {};
        return [
            { label: 'Feels Like', value: formatNumber(w.Feels_Like__c, '°C') },
            { label: 'Min', value: formatNumber(w.Temp_Min__c, '°C') },
            { label: 'Max', value: formatNumber(w.Temp_Max__c, '°C') }
        ];
    }
}