$(function() {
  var user_cache = {};
  var repo_cache = {};

  $.fn.apply_list = function(list) {
    var $this = $(this);
    $this.empty();
    $.each(list, function(i, el) {
      var opt = $("<option></option>").attr("value", el);
      $this.append(opt);
    });
    return this;
  }

  $("input[list]").datalist();

  $("#user-input").keypress(function(e) {
    var $this = $(this);
    var $list = $("#user-list");
    var input = $this.val();

    if (input.length < 2) {
      return;
    }

    if (user_cache[input]) {
      $list.apply_list(user_cache[input]);
      return;
    }

    $.getJSON(
      "https://api.github.com/legacy/user/search/"+input,
      function(data) {
        var users = $.map(data.users, function(u) {
          return u.username;
        });
        user_cache[input] = users;
        $list.apply_list(users);
      }
    );
  });
  $("#repo-input").focus(function(e) {
    var $this = $(this);
    var user = $("#user-input").val();
    var $list = $("#repo-list");

    if (!user) {
      return;
    }
    if (repo_cache[user]) {
      $list.apply_list(repo_cache[user]);
      return;
    }
    $.getJSON(
      "https://api.github.com/users/"+user+"/repos",
      function(data) {
        var repos = $.map(data, function(u) {
          return u.name;
        });
        repo_cache[user] = repos;
        $list.apply_list(repos);
      }
    );
  });
});
