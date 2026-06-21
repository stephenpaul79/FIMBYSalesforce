import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyLocationPicker extends LightningElement {
    @api label = 'Your Neighborhood';
    @api required = false;
    @track _selectedLocation = '';

    @api
    get selectedLocation() { return this._selectedLocation; }
    set selectedLocation(value) { this._selectedLocation = value; }

    @api showPopular = false;

    @track searchTerm = '';
    @track isGettingLocation = false;
    @track neighborhoods = [];
    
    // Mock neighborhood data (in production, load from Apex)
    allNeighborhoods = [
        { value: 'downtown-vancouver', label: 'Downtown Vancouver', details: 'Vancouver, BC', coordinates: { lat: 49.2827, lng: -123.1207 } },
        { value: 'kitsilano', label: 'Kitsilano', details: 'Vancouver, BC', coordinates: { lat: 49.2606, lng: -123.1563 } },
        { value: 'west-end', label: 'West End', details: 'Vancouver, BC', coordinates: { lat: 49.2889, lng: -123.1394 } },
        { value: 'gastown', label: 'Gastown', details: 'Vancouver, BC', coordinates: { lat: 49.2846, lng: -123.1098 } },
        { value: 'mount-pleasant', label: 'Mount Pleasant', details: 'Vancouver, BC', coordinates: { lat: 49.2634, lng: -123.1000 } },
        { value: 'commercial-drive', label: 'Commercial Drive', details: 'Vancouver, BC', coordinates: { lat: 49.2753, lng: -123.0693 } },
        { value: 'burnaby-heights', label: 'Burnaby Heights', details: 'Burnaby, BC', coordinates: { lat: 49.2544, lng: -123.0146 } },
        { value: 'richmond-center', label: 'Richmond Center', details: 'Richmond, BC', coordinates: { lat: 49.1666, lng: -123.1336 } },
        { value: 'north-vancouver', label: 'North Vancouver', details: 'North Vancouver, BC', coordinates: { lat: 49.3163, lng: -123.0926 } },
        { value: 'white-rock', label: 'White Rock', details: 'White Rock, BC', coordinates: { lat: 49.0267, lng: -122.8028 } }
    ];

    popularLocations = [
        { value: 'downtown-vancouver', label: 'Downtown' },
        { value: 'kitsilano', label: 'Kitsilano' },
        { value: 'west-end', label: 'West End' },
        { value: 'mount-pleasant', label: 'Mount Pleasant' }
    ];

    currentUserLocation = null;

    connectedCallback() {
        this.neighborhoods = [...this.allNeighborhoods];
    }

    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }

    get showResults() {
        return this.searchTerm.length > 0;
    }

    get showNoResults() {
        return this.searchTerm.length > 0 && this.filteredLocations.length === 0;
    }

    get filteredLocations() {
        if (!this.searchTerm) return [];
        
        const term = this.searchTerm.toLowerCase();
        return this.neighborhoods
            .filter(location => 
                location.label.toLowerCase().includes(term) || 
                location.details.toLowerCase().includes(term)
            )
            .map(location => ({
                ...location,
                isSelected: location.value === this._selectedLocation,
                distance: this.calculateDistance(location)
            }))
            .sort((a, b) => (a.distance || 999) - (b.distance || 999));
    }

    get selectedLocationLabel() {
        const location = this.neighborhoods.find(loc => loc.value === this._selectedLocation);
        return location?.label || '';
    }

    get selectedLocationDetails() {
        const location = this.neighborhoods.find(loc => loc.value === this._selectedLocation);
        return location?.details || '';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    async handleCurrentLocation() {
        if (!navigator.geolocation) {
            this.showError('Geolocation is not supported by this browser.');
            return;
        }

        this.isGettingLocation = true;

        try {
            const position = await this.getCurrentPosition();
            this.currentUserLocation = {
                lat: position.coords.latitude,
                lng: position.coords.longitude
            };

            // Find closest neighborhood
            const closest = this.findClosestNeighborhood(this.currentUserLocation);
            if (closest) {
                this.selectLocation(closest.value);
            }

        } catch (error) {
            console.error('Error getting location:', error);
            this.showError('Unable to get your current location.');
        } finally {
            this.isGettingLocation = false;
        }
    }

    handleLocationSelect(event) {
        const locationValue = event.currentTarget.dataset.location;
        this.selectLocation(locationValue);
    }

    handleChangeLocation() {
        this._selectedLocation = '';
        this.searchTerm = '';
    }

    selectLocation(locationValue) {
        this._selectedLocation = locationValue;
        this.searchTerm = '';

        // Fire selection event
        const selectionEvent = new CustomEvent('locationselected', {
            detail: {
                value: locationValue,
                location: this.neighborhoods.find(loc => loc.value === locationValue)
            }
        });
        this.dispatchEvent(selectionEvent);
    }

    getCurrentPosition() {
        return new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(
                resolve,
                reject,
                {
                    enableHighAccuracy: true,
                    timeout: 10000,
                    maximumAge: 300000 // 5 minutes
                }
            );
        });
    }

    findClosestNeighborhood(userLocation) {
        let closest = null;
        let minDistance = Infinity;

        this.neighborhoods.forEach(neighborhood => {
            const distance = this.calculateDistanceBetweenCoords(
                userLocation,
                neighborhood.coordinates
            );
            
            if (distance < minDistance) {
                minDistance = distance;
                closest = neighborhood;
            }
        });

        return closest;
    }

    calculateDistance(location) {
        if (!this.currentUserLocation || !location.coordinates) return null;
        
        return Math.round(
            this.calculateDistanceBetweenCoords(this.currentUserLocation, location.coordinates)
        );
    }

    calculateDistanceBetweenCoords(pos1, pos2) {
        const R = 6371; // Radius of the Earth in kilometers
        const dLat = this.deg2rad(pos2.lat - pos1.lat);
        const dLon = this.deg2rad(pos2.lng - pos1.lng);
        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(this.deg2rad(pos1.lat)) *
            Math.cos(this.deg2rad(pos2.lat)) *
            Math.sin(dLon / 2) *
            Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        const d = R * c; // Distance in kilometers
        return d;
    }

    deg2rad(deg) {
        return deg * (Math.PI / 180);
    }

    showError(message) {
        // In production, show toast or inline error
        console.error(message);
    }

    @api
    getSelectedLocation() {
        return this.neighborhoods.find(loc => loc.value === this._selectedLocation);
    }

    @api
    setLocation(locationValue) {
        this._selectedLocation = locationValue;
    }

    @api
    clearSelection() {
        this._selectedLocation = '';
        this.searchTerm = '';
    }
}