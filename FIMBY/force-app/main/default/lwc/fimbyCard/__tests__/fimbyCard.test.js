import { createElement } from "lwc";
import FimbyCard from "c/fimbyCard";
import { getAvatarTone } from "c/fimbyAvatarTone";

const PHOTO_URL = "https://example.com/photo-a.jpg";
const OTHER_PHOTO_URL = "https://example.com/photo-b.jpg";
const LAYOUTS = ["default", "list", "compact"];

function createCard(props = {}) {
  const element = createElement("c-fimby-card", { is: FimbyCard });
  Object.assign(element, {
    showHeader: true,
    showAvatar: true,
    userName: "Sarah Chen",
    ...props
  });
  document.body.appendChild(element);
  return element;
}

function avatarImages(element) {
  return element.shadowRoot.querySelectorAll(
    "img.avatar-image, img.compact-avatar"
  );
}

function initialsNodes(element) {
  return element.shadowRoot.querySelectorAll(
    ".avatar-initials, .compact-avatar-initials"
  );
}

function flush() {
  return Promise.resolve();
}

describe("c-fimby-card avatar fallback", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it.each(LAYOUTS)(
    "renders initials when there is no photo (%s layout)",
    (layout) => {
      const element = createCard({ layout });
      const initials = initialsNodes(element);
      expect(initials.length).toBeGreaterThan(0);
      initials.forEach((node) => expect(node.textContent).toBe("SC"));
      expect(avatarImages(element).length).toBe(0);
    }
  );

  it("uses a single initial for a one-word name", () => {
    const element = createCard({ userName: "Rosa" });
    expect(initialsNodes(element)[0].textContent).toBe("R");
  });

  it("falls back to ? when there is no usable name", () => {
    const element = createCard({ userName: "   " });
    expect(initialsNodes(element)[0].textContent).toBe("?");
  });

  it.each(LAYOUTS)(
    "renders the photo and no initials when a URL is set (%s layout)",
    (layout) => {
      const element = createCard({ layout, avatarUrl: PHOTO_URL });
      const images = avatarImages(element);
      expect(images.length).toBeGreaterThan(0);
      images.forEach((img) => expect(img.getAttribute("src")).toBe(PHOTO_URL));
      expect(initialsNodes(element).length).toBe(0);
    }
  );

  it.each(LAYOUTS)(
    "swaps to initials when the photo fails to load (%s layout)",
    async (layout) => {
      const element = createCard({ layout, avatarUrl: PHOTO_URL });
      avatarImages(element)[0].dispatchEvent(new CustomEvent("error"));
      await flush();
      expect(avatarImages(element).length).toBe(0);
      expect(initialsNodes(element)[0].textContent).toBe("SC");
    }
  );

  it("shows a new photo after a previous photo failed", async () => {
    const element = createCard({ avatarUrl: PHOTO_URL });
    avatarImages(element)[0].dispatchEvent(new CustomEvent("error"));
    await flush();
    expect(avatarImages(element).length).toBe(0);

    element.avatarUrl = OTHER_PHOTO_URL;
    await flush();
    const images = avatarImages(element);
    expect(images.length).toBe(1);
    expect(images[0].getAttribute("src")).toBe(OTHER_PHOTO_URL);
    expect(initialsNodes(element).length).toBe(0);
  });

  it("keeps the fallback when the same failed URL is assigned again", async () => {
    const element = createCard({ avatarUrl: PHOTO_URL });
    avatarImages(element)[0].dispatchEvent(new CustomEvent("error"));
    await flush();

    element.avatarUrl = PHOTO_URL;
    await flush();
    expect(avatarImages(element).length).toBe(0);
    expect(initialsNodes(element).length).toBe(1);
  });

  it.each(LAYOUTS)(
    "renders no avatar when showAvatar is false (%s layout)",
    (layout) => {
      const element = createCard({
        layout,
        showAvatar: false,
        avatarUrl: PHOTO_URL
      });
      expect(avatarImages(element).length).toBe(0);
      expect(initialsNodes(element).length).toBe(0);
    }
  );

  it("exposes the header avatar as a labelled control when it links to a profile", () => {
    const element = createCard({
      posterProfileUrl: "/neighbour?id=003000000000001"
    });
    const wrapper = element.shadowRoot.querySelector(".user-avatar");
    expect(wrapper.getAttribute("role")).toBe("button");
    expect(wrapper.getAttribute("tabindex")).toBe("0");
    expect(wrapper.getAttribute("aria-label")).toBe(
      "View Sarah Chen's profile"
    );
  });

  it("does not present the header avatar as a control without a profile link", () => {
    const element = createCard();
    const wrapper = element.shadowRoot.querySelector(".user-avatar");
    expect(wrapper.getAttribute("role")).toBeNull();
    expect(wrapper.getAttribute("tabindex")).toBeNull();
    expect(wrapper.getAttribute("aria-label")).toBeNull();
  });

  it.each(LAYOUTS)(
    "colours the initials circle with the person's earth tone (%s layout)",
    (layout) => {
      const element = createCard({ layout });
      const circle = element.shadowRoot.querySelector(
        ".avatar-placeholder, .compact-avatar-initials"
      );
      expect(circle.getAttribute("style")).toContain(
        getAvatarTone("Sarah Chen")
      );
    }
  );

  it.each(LAYOUTS)(
    "keys the tone on the owner's Contact Id, not the name (%s layout)",
    (layout) => {
      const element = createCard({ layout, contactId: "003OL00000tXhWNYA0" });
      const circle = element.shadowRoot.querySelector(
        ".avatar-placeholder, .compact-avatar-initials"
      );
      expect(circle.getAttribute("style")).toContain("--fimby-earth-terracotta");
      expect(circle.classList).not.toContain("avatar-org");
    }
  );

  it.each(LAYOUTS)(
    "renders an organisation without a logo as a rounded square (%s layout)",
    (layout) => {
      const element = createCard({
        layout,
        userName: "The Life",
        isOrgPoster: true,
        contactId: "003OL00000xUb3OYAS",
        organizationAccountId: "001OL00000qGuI3YAK"
      });
      const square = element.shadowRoot.querySelector(
        ".avatar-placeholder, .compact-avatar-initials"
      );
      expect(square.classList).toContain("avatar-org");
      expect(square.getAttribute("style")).toContain("--fimby-earth-ochre");
      expect(square.textContent).toBe("TL");
    }
  );
});
