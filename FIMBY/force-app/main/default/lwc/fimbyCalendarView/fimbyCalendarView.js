import { LightningElement, track } from 'lwc';
export default class FimbyCalendarView extends LightningElement {
    @track currentDate = new Date();
    @track calendarDays = [];

    get currentMonthYear() {
        return this.currentDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
    }

    connectedCallback() { this.generateCalendar(); }

    generateCalendar() {
        const year = this.currentDate.getFullYear();
        const month = this.currentDate.getMonth();
        const today = new Date();
        const lastDay = new Date(year, month + 1, 0);
        const days = [];

        for (let i = 1; i <= lastDay.getDate(); i++) {
            const date = new Date(year, month, i);
            days.push({
                id: `day-${i}`,
                dayNumber: i,
                date: date.toISOString().split('T')[0],
                cssClass: this.getDayClass(date, today),
                hasEvents: Math.random() > 0.8
            });
        }
        this.calendarDays = days;
    }

    getDayClass(date, today) {
        let classes = ['calendar-day'];
        if (date.toDateString() === today.toDateString()) classes.push('today');
        return classes.join(' ');
    }

    handlePrevMonth() { this.currentDate.setMonth(this.currentDate.getMonth() - 1); this.generateCalendar(); }
    handleNextMonth() { this.currentDate.setMonth(this.currentDate.getMonth() + 1); this.generateCalendar(); }
    handleDayClick(event) { console.log('Day clicked:', event.currentTarget.dataset.date); }
    handleBack() { window.history.back(); }
    handleTabChange(event) { console.log('Tab change:', event.detail.tab); }
}