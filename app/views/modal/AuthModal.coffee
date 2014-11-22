ModalView = require 'views/kinds/ModalView'
template = require 'templates/modal/auth'
{loginUser, createUser, me} = require 'lib/auth'
forms = require 'lib/forms'
User = require 'models/User'
application  = require 'application'

module.exports = class AuthModal extends ModalView
  id: 'auth-modal'
  template: template
  mode: 'signup' # or 'login'

  events:
    # login buttons
    'click #switch-to-signup-button': 'onSignupInstead'
    'click #switch-to-login-button': 'onLoginInstead'
    'click #confirm-age': 'checkAge'
    'click #github-login-button': 'onGitHubLoginClicked'
    'submit': 'onSubmitForm' # handles both submit buttons
    'keyup #name': 'onNameChange'
    'click #gplus-login-button': 'onClickGPlusLogin'

  subscriptions:
    'errors:server-error': 'onServerError'
    'auth:logging-in-with-facebook': 'onLoggingInWithFacebook'

  constructor: (options) ->
    @onNameChange = _.debounce @checkNameExists, 500
    super options

  getRenderData: ->
    c = super()
    c.showRequiredError = @options.showRequiredError
    c.title = {0: 'short', 1: 'long'}[me.get('testGroupNumber') % 2]
    c.descriptionOn = {0: 'yes', 1: 'no'}[Math.floor(me.get('testGroupNumber')/2) % 2]
    if @mode is 'signup'
      application.tracker.identify authModalTitle: c.title
      application.tracker.trackEvent 'Started Signup', authModalTitle: c.title, descriptionOn: c.descriptionOn
    c.mode = @mode
    c.formValues = @previousFormInputs or {}
    c.onEmployersPage = Backbone.history.fragment is "employers"
    c.me = me
    c

  afterInsert: ->
    super()
    _.delay (=> application.router.renderLoginButtons()), 500
    _.delay (=> $('input:visible:first', @$el).focus()), 500

  onSignupInstead: (e) ->
    @mode = 'signup'
    @previousFormInputs = forms.formToObject @$el
    @render()
    _.delay application.router.renderLoginButtons, 500

  onLoginInstead: (e) ->
    @mode = 'login'
    @previousFormInputs = forms.formToObject @$el
    @render()
    _.delay application.router.renderLoginButtons, 500

  onSubmitForm: (e) ->
    e.preventDefault()
    if @mode is 'login' then @loginAccount() else @createAccount()
    false

  checkAge: (e) ->
    $('#signup-button', @$el).prop 'disabled', not $(e.target).prop('checked')

  loginAccount: ->
    forms.clearFormAlerts(@$el)
    userObject = forms.formToObject @$el
    res = tv4.validateMultiple userObject, User.schema
    return forms.applyErrorsToForm(@$el, res.errors) unless res.valid
    @enableModalInProgress(@$el) # TODO: part of forms
    loginUser(userObject)

  createAccount: ->
    forms.clearFormAlerts(@$el)
    userObject = forms.formToObject @$el
    delete userObject.subscribe
    delete userObject['confirm-age']
    delete userObject.name if userObject.name is ''
    userObject.name = @suggestedName if @suggestedName
    for key, val of me.attributes when key in ['preferredLanguage', 'testGroupNumber', 'dateCreated', 'wizardColor1', 'name', 'music', 'volume', 'emails']
      userObject[key] ?= val
    subscribe = @$el.find('#subscribe').prop('checked')
    userObject.emails ?= {}
    userObject.emails.generalNews ?= {}
    userObject.emails.generalNews.enabled = subscribe
    res = tv4.validateMultiple userObject, User.schema
    return forms.applyErrorsToForm(@$el, res.errors) unless res.valid
    Backbone.Mediator.publish "auth:signed-up", {}
    window.tracker?.trackEvent 'Finished Signup'
    @enableModalInProgress(@$el)
    createUser userObject, null, window.nextLevelURL

  onLoggingInWithFacebook: (e) ->
    modal = $('.modal:visible', @$el)
    @enableModalInProgress(modal) # TODO: part of forms

  onServerError: (e) -> # TODO: work error handling into a separate forms system
    @disableModalInProgress(@$el)

  checkNameExists: =>
    name = $('#name', @$el).val()
    return forms.clearFormAlerts(@$el) if name is ''
    User.getUnconflictedName name, (newName) =>
      forms.clearFormAlerts(@$el)
      if name is newName
        @suggestedName = undefined
      else
        @suggestedName = newName
        forms.setErrorToProperty @$el, 'name', "That name is taken! How about #{newName}?", true

  onGitHubLoginClicked: ->
    Backbone.Mediator.publish 'auth:log-in-with-github', {}

  gplusAuthSteps: [
    { i18n: 'login.authenticate_gplus', done: false }
    { i18n: 'login.load_profile', done: false }
    { i18n: 'login.load_email', done: false }
    { i18n: 'login.finishing', done: false }
  ]

  onClickGPlusLogin: ->
    step.done = false for step in @gplusAuthSteps
    handler = application.gplusHandler

    @listenToOnce handler, 'logged-in', ->
      @gplusAuthSteps[0].done = true
      @renderGPlusAuthChecklist()
      handler.loginCodeCombat()
      @listenToOnce handler, 'person-loaded', ->
        @gplusAuthSteps[1].done = true
        @renderGPlusAuthChecklist()

      @listenToOnce handler, 'email-loaded', ->
        @gplusAuthSteps[2].done = true
        @renderGPlusAuthChecklist()

      @listenToOnce handler, 'logging-into-codecombat', ->
        @gplusAuthSteps[3].done = true
        @renderGPlusAuthChecklist()

  renderGPlusAuthChecklist: ->
    template = require 'templates/modal/auth-modal-gplus-checklist'
    el = $(template({steps: @gplusAuthSteps}))
    el.i18n()
    @$el.find('.modal-body:visible').empty().append(el)
    @$el.find('.modal-footer').remove()
