import { LightningElement, track } from 'lwc';
export default class FimbyEventCreator extends LightningElement {
    @track eventTitle = '';
    @track eventDescription = '';
    @track eventDate = '';
    @track eventTime = '';
    @track eventLocation = null;

    handleTitleChange(event) { this.eventTitle = event.target.value; }
    handleDescriptionChange(event) { this.eventDescription = event.target.value; }
    handleDateChange(event) { this.eventDate = event.target.value; }
    handleTimeChange(event) { this.eventTime = event.target.value; }
    handleLocationChange(event) { this.eventLocation = event.detail.location; }

    handleCreateEvent() {
        const eventData = {
            title: this.eventTitle,
            description: this.eventDescription,
            date: this.eventDate,
            time: this.eventTime,
            location: this.eventLocation
        };
        console.log('Create event:', eventData);
    }

    handleBack() { window.history.back(); }
}