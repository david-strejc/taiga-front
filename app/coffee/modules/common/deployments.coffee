###
# Copyright (C) 2014 Andrey Antukh <niwi@niwi.be>
# Copyright (C) 2014 Jesús Espino Garcia <jespinog@gmail.com>
# Copyright (C) 2014 David Barragán Merino <bameda@dbarragan.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# File: modules/common/deployments.coffee
###

taiga = @.taiga
sizeFormat = @.taiga.sizeFormat
bindOnce = @.taiga.bindOnce
bindMethods = @.taiga.bindMethods

module = angular.module("taigaCommon")

class DeploymentsController extends taiga.Controller
    @.$inject = ["$scope", "$rootScope", "$tgRepo", "$tgResources", "$tgConfirm", "$q"]

    constructor: (@scope, @rootscope, @repo, @rs, @confirm, @q) ->
        bindMethods(@)
        @.type = null
        @.objectId = null
        @.projectId = null

        @.uploadingDeployments = []
        @.deployments = []
        @.deploymentsCount = 0
        @.deprecatedDeploymentsCount = 0
        @.showDeprecated = false

    initialize: (type, objectId) ->
        @.type = type
        @.objectId = objectId
        @.projectId = @scope.projectId

        console.log @.type
        console.log @.objectId
        console.log @.projectId

    loadDeployments: ->
        return @.deployments if not @.objectId

        urlname = "deployments"
        console.log urlname
        console.log @rs

        return @rs.deployments.list(urlname, @.objectId, @.projectId).then (deployments) =>
            console.log urlname
            @.deployments= _.sortBy(deployments, "order")
            console.log @.deployments
            return deployments

    _createDeployment: (deployment) ->
        urlName = "deployments"

        promise = @rs.deployments.create(urlName, @.projectId, @.objectId, deployment)
        promise = promise.then (data) =>
            data.isCreatedRightNow = true

            index = @.uploadingDeployments.indexOf(deployment)
            @.uploadingDeployments.splice(index, 1)
            @.deployments.push(data)
            @rootscope.$broadcast("deployment:create")

        promise = promise.then null, (data) =>
            @scope.$emit("deployments:size-error") if data.status == 413
            index = @.uploadingDeployments.indexOf(deployment)
            @.uploadingDeployments.splice(index, 1)
            @confirm.notify("error", "We have not been able to upload '#{deployment.name}'.
                                      #{data.data._error_message}")
            return @q.reject(data)

        return promise

    # Add uploading deployments tracking.
    addUploadingDeployments: (deployments) ->
        @.uploadingDeployments = _.union(@.uploadingDeployments, deployments)

    # Change order of deployments in a ordered list.
    # This function is mainly executed after sortable ends.
    reorderDeployment: (deployment, newIndex) ->
        oldIndex = @.deployments.indexOf(deployment)
        return if oldIndex == newIndex

        @.deployments.splice(oldIndex, 1)
        @.deployments.splice(newIndex, 0, deployment)

        _.each(@.deployments, (x,i) -> x.order = i+1)

    # Persist one concrete deployments.
    # This function is mainly used when user clicks
    # to save button for save one unique deployment.
    updateDeployment: (deployment) ->
        onSuccess = =>
            @.updateCounters()
            @rootscope.$broadcast("deployment:edit")

        onError = (response) =>
            $scope.$emit("deployments:size-error") if response.status == 413
            @confirm.notify("error")
            return @q.reject()

        return @repo.save(deployment).then(onSuccess, onError)

    # Persist all pending modifications on deployments.
    # This function is used mainly for persist the order
    # after sorting.
    saveDeployments: ->
        return @repo.saveAll(@.deployments).then null, =>
            for item in @.deployments
                item.revert()
            @.deployments = _.sortBy(@.deployments, "order")

    # Remove one concrete deployment
    removeDeployment: (deployment) ->
        title = "Delete deployment"  #TODO: i18in
        message = "the deployment'#{deployment.name}'" #TODO: i18in

        return @confirm.askOnDelete(title, message).then (finish) =>
            onSuccess = =>
                finish()
                index = @.deployments.indexOf(deployment)
                @.deploments.splice(index, 1)
                @.updateCounters()
                @rootscope.$broadcast("deployment:delete")

            onError = =>
                finish(false)
                @confirm.notify("error", null, "We have not been able to delete #{message}.")
                return @q.reject()

            return @repo.remove(deployment).then(onSuccess, onError)

    # Function used in template for filter visible deployments
    filterDeployments: (item) ->
        if @.showDeprecated
            return true
        return not item.is_deprecated


DeploymentsDirective = ($config, $confirm, $templates) ->
    template = $templates.get("deployment/deployments.html", true)

    link = ($scope, $el, $attrs, $ctrls) ->
        $ctrl = $ctrls[0]
        $model = $ctrls[1]

        bindOnce $scope, $attrs.ngModel, (value) ->
            $ctrl.initialize($attrs.type, value.id)
            $ctrl.loadDeployments()

        tdom = $el.find("div.deployment-body.sortable")
        tdom.sortable({
            items: "div.single-deployment"
            handle: "a.settings.icon.icon-drag-v"
            containment: ".deployments"
            dropOnEmpty: true
            scroll: false
            tolerance: "pointer"
            placeholder: "sortable-placeholder single-deployment"
        })

        tdom.on "sortstop", (event, ui) ->
            deployment = ui.item.scope().attach
            newIndex = ui.item.index()

            $ctrl.reorderDeployment(deployment, newIndex)
            $ctrl.saveDeployments().then ->
                $scope.$emit("deployment:edit")

        showSizeInfo = ->
            $el.find(".size-info").removeClass("hidden")

        $scope.$on "deployments:size-error", ->
            showSizeInfo()

        $el.on "change", ".deployments-header input", (event) ->
            files = _.toArray(event.target.files)
            return if files.length < 1

            $scope.$apply ->
                $ctrl.addUploadingDeployments(files)
                $ctrl.createDeployments(files)

        $el.on "click", ".more-deployments", (event) ->
            event.preventDefault()
            target = angular.element(event.currentTarget)

            $scope.$apply ->
                $ctrl.showDeprecated = not $ctrl.showDeprecated

            target.find("span.text").addClass("hidden")
            if $ctrl.showDeprecated
                target.find("span[data-type=hide]").removeClass("hidden")
                target.find("more-deployments-num").addClass("hidden")
            else
                target.find("span[data-type=show]").removeClass("hidden")
                target.find("more-deployments-num").removeClass("hidden")

        $scope.$on "$destroy", ->
            $el.off()

    templateFn = ($el, $attrs) ->
        maxFileSize = $config.get("maxUploadFileSize", null)
        maxFileSize = sizeFormat(maxFileSize) if maxFileSize
        maxFileSizeMsg = if maxFileSize then $translation.instant("DEPLOYMENT.MAX_UPLOAD_SIZE") else ""
        maxFileSize = 4000
        ctx = {
            type: $attrs.type
            maxFileSize: maxFileSize
            maxFileSizeMsg: maxFileSizeMsg
        }
        return template(ctx)

    return {
        require: ["tgDeployments", "ngModel"]
        controller: DeploymentsController
        controllerAs: "ctrl"
        restrict: "AE"
        scope: true
        link: link
        template: templateFn
    }

module.directive("tgDeployments", ["$tgConfig", "$tgConfirm", "$tgTemplate", DeploymentsDirective])


#DeploymentDirective = ($template, $compile) ->
#    template = $template.get("deployment/deployment.html", true)
#
#    link = ($scope, $el, $attrs, $ctrl) ->
#        render = (deployment, edit=false) ->
#            permissions = $scope.project.my_permissions
#            modifyPermission = permissions.indexOf("modify_#{$ctrl.type}") > -1
#
#            ctx = {
#                id: deployment.id
#                name: deployment.name
#                created_date: moment(deployment.created_date).format("DEPLOYMENT.DATE")
#                url: deployment.url
#                size: sizeFormat(deployment.size)
#                description: deployment.description
#                isDeprecated: deployment.is_deprecated
#                modifyPermission: modifyPermission
#            }
#
#            if edit
#                html = $compile(templateEdit(ctx))($scope)
#            else
#                html = $compile(template(ctx))($scope)
#
#            $el.html(html)
#
#            if deployment.is_deprecated
#                $el.addClass("deprecated")
#                $el.find("input:checkbox").prop('checked', true)
#
#        saveDeployment = ->
#            deployment.description = $el.find("input[name='description']").val()
#            deployment.is_deprecated = $el.find("input[name='is-deprecated']").prop("checked")
#
#            $scope.$apply ->
#                $ctrl.updateDeployment(deployment).then ->
#                    render(deployment, false)
#
#        ## Actions (on edit mode)
#        $el.on "click", "a.editable-settings.icon-floppy", (event) ->
#            event.preventDefault()
#            saveDeployment()
#
#        $el.on "keyup", "input[name=description]", (event) ->
#            if event.keyCode == 13
#                saveDeployment()
#            else if event.keyCode == 27
#                render(deployment, false)
#
#        $el.on "click", "a.editable-settings.icon-delete", (event) ->
#            event.preventDefault()
#            render(deployment, false)
#
#        ## Actions (on view mode)
#        $el.on "click", "a.settings.icon-edit", (event) ->
#            event.preventDefault()
#            render(deployment, true)
#            $el.find("input[name='description']").focus().select()
#
#        $el.on "click", "a.settings.icon-delete", (event) ->
#            event.preventDefault()
#            $scope.$apply ->
#                $ctrl.removeDeployment(deployment)
#
#        $scope.$on "$destroy", ->
#            $el.off()
#
#        # Bootstrap
#        deployment = $scope.$eval($attrs.tgDeployment)
#        render(deployment, deployment.isCreatedRightNow)
#        if deployment.isCreatedRightNow
#            $el.find("input[name='description']").focus().select()
#
#    return {
#        link: link
#        require: "^tgDeployments"
#        restrict: "AE"
#    }
#
#module.directive("tgDeploment", ["$tgTemplate", "$compile", DeploymentDirective])
