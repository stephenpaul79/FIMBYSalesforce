/**
 * Optional: Mark FIMBY sections as visible when they scroll into view
 * Add this script to your theme (e.g. in a custom plugin or theme footer) so that
 * .fimby-scroll-section elements get class .is-visible when they enter the viewport.
 * Use together with fimby-scroll-sections.css.
 */
(function () {
  var sections = document.querySelectorAll('.fimby-scroll-section');
  if (!sections.length) return;

  var observer = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
        }
      });
    },
    { rootMargin: '0px 0px -10% 0px', threshold: 0 }
  );

  sections.forEach(function (el) {
    observer.observe(el);
  });
})();
