import { LightningElement, track } from "lwc";

export default class FimbyPublicHeader extends LightningElement {
    @track _menuOpen = false;

    get mobileNavClass() {
        return this._menuOpen ? "mobile-nav open" : "mobile-nav";
    }

    get hamburgerLine1() {
        return this._menuOpen ? "bar bar-1 active" : "bar bar-1";
    }

    get hamburgerLine2() {
        return this._menuOpen ? "bar bar-2 active" : "bar bar-2";
    }

    get hamburgerLine3() {
        return this._menuOpen ? "bar bar-3 active" : "bar bar-3";
    }

    handleToggleMenu() {
        this._menuOpen = !this._menuOpen;
    }
}