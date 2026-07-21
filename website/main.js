// Mobile navigation toggle
(function () {
  var toggle = document.querySelector('.nav-toggle');
  var menu = document.querySelector('.mobile-nav');
  if (!toggle || !menu) return;

  toggle.addEventListener('click', function () {
    var open = menu.classList.toggle('open');
    menu.hidden = !open;
    toggle.setAttribute('aria-expanded', String(open));
  });

  // Close the menu after tapping a link
  menu.querySelectorAll('a').forEach(function (link) {
    link.addEventListener('click', function () {
      menu.classList.remove('open');
      menu.hidden = true;
      toggle.setAttribute('aria-expanded', 'false');
    });
  });
})();
