import { createElement } from "lwc";
import FimbyAvatar from "c/fimbyAvatar";

function mount(props) {
  const element = createElement("c-fimby-avatar", { is: FimbyAvatar });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const wrapper = (el) => el.shadowRoot.querySelector(".avatar");

describe("c-fimby-avatar", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows initials on the identity's earth tone when there is no photo", () => {
    const el = mount({ name: "Amir Haddad", contactId: "003OL00000tXhWNYA0" });
    expect(el.shadowRoot.querySelector("img")).toBeNull();
    expect(el.shadowRoot.querySelector(".avatar-initials").textContent).toBe("AH");
    expect(wrapper(el).getAttribute("style")).toContain("--fimby-earth-terracotta");
  });

  it("shows the photo with an empty alt when a source exists", () => {
    const el = mount({ name: "Sarah Chen", src: "https://x.test/sarah.jpg" });
    const img = el.shadowRoot.querySelector("img");
    expect(img.getAttribute("src")).toBe("https://x.test/sarah.jpg");
    expect(img.getAttribute("alt")).toBe("");
  });

  it("falls back to initials when the image fails, and retries a new source", async () => {
    const el = mount({ name: "Sarah Chen", src: "https://x.test/broken.jpg" });
    el.shadowRoot.querySelector("img").dispatchEvent(new CustomEvent("error"));
    await Promise.resolve();
    expect(el.shadowRoot.querySelector("img")).toBeNull();
    expect(el.shadowRoot.querySelector(".avatar-initials").textContent).toBe("SC");

    el.src = "https://x.test/fresh.jpg";
    await Promise.resolve();
    expect(el.shadowRoot.querySelector("img").getAttribute("src")).toBe(
      "https://x.test/fresh.jpg"
    );
  });

  it("ignores a stale error from a previous source", async () => {
    const el = mount({ name: "Sarah Chen", src: "https://x.test/old.jpg" });
    const img = el.shadowRoot.querySelector("img");
    el.src = "https://x.test/new.jpg";
    await Promise.resolve();
    img.setAttribute("src", "https://x.test/old.jpg");
    img.dispatchEvent(new CustomEvent("error"));
    await Promise.resolve();
    expect(el.shadowRoot.querySelector("img")).not.toBeNull();
  });

  it("clamps the size to 16-128px and defaults invalid values", async () => {
    const el = mount({ name: "A", size: 400 });
    expect(wrapper(el).getAttribute("style")).toContain("--fimby-avatar-size: 128px");
    el.size = 2;
    await Promise.resolve();
    expect(wrapper(el).getAttribute("style")).toContain("--fimby-avatar-size: 16px");
    el.size = "abc";
    await Promise.resolve();
    expect(wrapper(el).getAttribute("style")).toContain("--fimby-avatar-size: 40px");
  });

  it("is decorative by default and semantic when labelled", async () => {
    const el = mount({ name: "Maya Chen" });
    expect(wrapper(el).getAttribute("aria-hidden")).toBe("true");
    expect(wrapper(el).getAttribute("role")).toBeNull();
    el.label = "Maya Chen";
    await Promise.resolve();
    expect(wrapper(el).getAttribute("role")).toBe("img");
    expect(wrapper(el).getAttribute("aria-label")).toBe("Maya Chen");
    expect(wrapper(el).getAttribute("aria-hidden")).toBeNull();
  });

  it("renders organisations as rounded squares keyed on the org identity", () => {
    const el = mount({
      name: "The Life",
      contactId: "003OL00000xUb3OYAS",
      organizationAccountId: "001OL00000qGuI3YAK",
      isOrganization: true
    });
    expect(wrapper(el).classList).toContain("avatar-org");
    expect(wrapper(el).getAttribute("style")).toContain("--fimby-earth-ochre");
    expect(el.shadowRoot.querySelector(".avatar-initials").textContent).toBe("TL");
  });
});
