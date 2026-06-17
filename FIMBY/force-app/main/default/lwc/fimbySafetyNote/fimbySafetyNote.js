import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';

const GUIDELINES_PATH = '/community-guidelines';

/**
 * Warm, neighbourly first-meeting safety guidance shown at the handoff moment
 * (borrow approval/pickup, event RSVP, bulk buy pickup). Thin wrapper over
 * c-fimby-inline-banner (info variant) — adds the multi-line meeting copy, a
 * Community Standards link, and a per-session dismiss. No persistence in v1.
 */
export default class FimbySafetyNote extends NavigationMixin(LightningElement) {
    /** Optional override for the headline line beside the info icon. */
    @api headline = 'Meeting a neighbour for the first time? A few gentle reminders.';

    @track _dismissed = false;

    get isVisible() {
        return !this._dismissed;
    }

    get guidelinesUrl() {
        return GUIDELINES_PATH;
    }

    handleDismiss() {
        this._dismissed = true;
        this.dispatchEvent(new CustomEvent('dismiss'));
    }

    handleStandardsLink(event) {
        event.preventDefault();
        navigate(this, GUIDELINES_PATH);
    }
}
