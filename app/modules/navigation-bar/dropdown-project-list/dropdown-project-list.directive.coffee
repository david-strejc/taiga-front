DropDownProjectListDirective = () ->
    link = (scope, elm, attrs, controller) ->
      #TODO
      console.log "ASDASDASD", controller

    directive = {
        link: link
        templateUrl: "navigation-bar/dropdown-project-list/dropdown-project-list.html"
        controller: "ProjectsController"
        scope: {}
        bindToController: true
        controllerAs: "controller"
    }

    return directive

angular.module("taigaNavigationBar").directive("tgDropDownProjectList",
    DropDownProjectListDirective)
