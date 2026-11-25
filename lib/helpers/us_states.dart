// lib/helpers/us_states.dart
//
// The 50 US states and the District of Columbia: USPS code and English
// name, and the lookup that reads either from a Polymarket label
// ("Texas", "TX", "Washington D.C."). Used by the Predictions state map
// (special_event_map.dart) to tie an event's markets to the map's
// outlines (us_map_geometry.dart).

/// Every state's (and DC's) English name by USPS code, alphabetical by
/// code.
const Map<String, String> kUsStateNames = {
  'AK': 'Alaska',
  'AL': 'Alabama',
  'AR': 'Arkansas',
  'AZ': 'Arizona',
  'CA': 'California',
  'CO': 'Colorado',
  'CT': 'Connecticut',
  'DC': 'District of Columbia',
  'DE': 'Delaware',
  'FL': 'Florida',
  'GA': 'Georgia',
  'HI': 'Hawaii',
  'IA': 'Iowa',
  'ID': 'Idaho',
  'IL': 'Illinois',
  'IN': 'Indiana',
  'KS': 'Kansas',
  'KY': 'Kentucky',
  'LA': 'Louisiana',
  'MA': 'Massachusetts',
  'MD': 'Maryland',
  'ME': 'Maine',
  'MI': 'Michigan',
  'MN': 'Minnesota',
  'MO': 'Missouri',
  'MS': 'Mississippi',
  'MT': 'Montana',
  'NC': 'North Carolina',
  'ND': 'North Dakota',
  'NE': 'Nebraska',
  'NH': 'New Hampshire',
  'NJ': 'New Jersey',
  'NM': 'New Mexico',
  'NV': 'Nevada',
  'NY': 'New York',
  'OH': 'Ohio',
  'OK': 'Oklahoma',
  'OR': 'Oregon',
  'PA': 'Pennsylvania',
  'RI': 'Rhode Island',
  'SC': 'South Carolina',
  'SD': 'South Dakota',
  'TN': 'Tennessee',
  'TX': 'Texas',
  'UT': 'Utah',
  'VA': 'Virginia',
  'VT': 'Vermont',
  'WA': 'Washington',
  'WI': 'Wisconsin',
  'WV': 'West Virginia',
  'WY': 'Wyoming',
};

final Map<String, String> _codeByName = {
  for (final e in kUsStateNames.entries) _key(e.value): e.key,
  _key('Washington DC'): 'DC',
  _key('Washington D.C.'): 'DC',
  _key('Washington, D.C.'): 'DC',
  _key('D.C.'): 'DC',
};

String _key(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[.,]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The USPS code of the state [label] names: its English name in any case
/// ("Texas", "new york", "Washington D.C."), or its code written in
/// capitals ("TX"; "or", "in" and "me" are words, so a code is read in
/// capitals only). Null for anything else.
String? usStateCodeOf(String label) {
  final t = label.trim();
  if (t.length == 2 && kUsStateNames.containsKey(t)) return t;
  return _codeByName[_key(t)];
}
