/**
 * @file
 * Global utilities.
 *
 */
(function (Drupal) {

  'use strict';

  Drupal.behaviors.uncw_barrio = {
    attach: function (context, settings) {

    }
  };

})(Drupal);

/**
 * Footer social icons: swap to the gold variant on hover/focus (as library.uncw.edu does).
 */
(function (Drupal, once) {
  Drupal.behaviors.uncwFooterSocial = {
    attach: function (context) {
      once('uncw-social', '.f-col-four img[data-hover]', context).forEach(function (img) {
        var link = img.closest('a') || img;
        var hover = function () { img.src = img.dataset.hover; };
        var rest = function () { img.src = img.dataset.rest; };
        link.addEventListener('mouseenter', hover);
        link.addEventListener('focus', hover);
        link.addEventListener('mouseleave', rest);
        link.addEventListener('blur', rest);
      });
    }
  };
})(Drupal, once);
