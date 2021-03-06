ModalView = require 'views/kinds/ModalView'
template = require 'templates/play/level/modal/reload-level-modal'

module.exports = class ReloadLevelModal extends ModalView
  id: '#reload-level-modal'
  template: template

  events:
    'click #restart-level-confirm-button': 'onClickRestart'

  onClickRestart: (e) ->
    if key.shift
      Backbone.Mediator.publish 'level:restart', {}
    else
      Backbone.Mediator.publish 'tome:reload-code', {}
