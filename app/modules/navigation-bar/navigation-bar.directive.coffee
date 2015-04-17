NavigationBarDirective = () ->
    directive = {
        link: link,
        templateUrl: "navigation-bar/navigation-bar.html"
    }

    return directive

    link = (scope, elm, attrs) ->
      #TODO


angular.module("taigaNavigationBar").directive("tgNavigationBar",
    NavigationBarDirective)
