/// The local closed action set. Never serialize user-specific capabilities.
class AdvisorCapabilityManifest {
  AdvisorCapabilityManifest._();
  static const version = '3';
  static const localActions = {'switch_to_limit', 'open_leverage_settings'};
  static const navigationActions = {
    'open_money_tab',
    'open_predictions_tab',
    'open_trading_tab',
    'open_support',
    'open_settings',
    'open_market_by_slug',
    'open_hl_market',
  };
  static bool isEnabled(String actionId) =>
      navigationActions.contains(actionId) || localActions.contains(actionId);

  /// Refuse all unspecified parameters, including order size, side and leverage.
  static bool validParams(String actionId, Map<String, dynamic> params) {
    if (!isEnabled(actionId)) return false;
    if (actionId == 'open_market_by_slug') {
      return params.keys.every((k) => k == 'slug') &&
          params['slug'] is String &&
          RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,199}$')
              .hasMatch(params['slug'] as String);
    }
    if (actionId == 'open_hl_market') {
      return params.keys.every((k) => k == 'coin' || k == 'kind') &&
          params['coin'] is String &&
          RegExp(r'^[a-zA-Z0-9@][a-zA-Z0-9@:_/.-]{0,79}$')
              .hasMatch(params['coin'] as String) &&
          (params['kind'] == null ||
              params['kind'] == 'spot' ||
              params['kind'] == 'perp');
    }
    return params.isEmpty;
  }
}
