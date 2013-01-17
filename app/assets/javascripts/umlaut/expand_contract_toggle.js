/* expand_contract_toggle.js: Support for show more/hide more in lists of umlaut content.
   
   The JS needs to swap out the image for expand/contract toggle. AND we need
   the URL it swaps in to be an ABSOLUTE url when we're using partial html
   widget. 
   
   So we swap in a non-fingerprinted URL, even if the original was asset
   pipline fingerprinted. sorry, best way to make it work!
*/
jQuery(document).ready(function($) {
  $(".collapse-toggle").live("click", function(event) {
    $(this).collapse('toggle');
    event.preventDefault();
    return false;
  });
  $(".collapse").live("shown", function(event) {
    // Update the icon
    $(this).parent().find('.collapse-toggle i').removeClass("umlaut_icons-list-closed").addClass("umlaut_icons-list-open");
    // Update the action label
    $(this).parent().find(".expand_contract_action_label").text("Hide ");
  });
  $(".collapse").live("hidden", function(event) {
    // Update the icon
    $(this).parent().find('.collapse-toggle i').removeClass("umlaut_icons-list-open").addClass("umlaut_icons-list-closed");
    // Update the action label
    $(this).parent().find(".expand_contract_action_label").text("Show ");
  });
});