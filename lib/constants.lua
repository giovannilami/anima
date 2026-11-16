local NONE = 'none'
local OCTAVE = 'octave'
local MUTE = 'mute'
local RESET_SELF = 'reset self'
local RESET_OTHER = 'reset other'
local RESET_ALL = 'reset all'

local FORWARD = 'forward'
local REVERSE = 'reverse'
local PENDULUM = 'pendulum'
local RANDOM = 'random'

local AUDIO = 'audio'
local MIDI = 'midi'
local AUDIO_MIDI = 'audio + midi'
local CROW_II_JF = 'crow ii jf'
local CROW_II_SC = 'ER-301'
local CROW_CV = 'crow cv'
local CROW_CV_JF = 'crow cv + JF'
local AUDIO_CV_JF = 'audio + cv + JF'
local GRID_LENGTH = 16
local GRID_HEIGHT = 8

local constants = {
  GRID_HEIGHT = GRID_HEIGHT,
  GRID_LENGTH = GRID_LENGTH,
  CANVAS_HEIGHT = GRID_HEIGHT - 1,
  CANVAS_LENGTH = GRID_LENGTH,
  GRID_NAV_ROW = 8,
  PAGE_CANVAS = 1,
  PAGE_LINES = 2,
  PAGE_INTERSECTIONS = 3,
  PAGE_NAMES = {'canvas', 'lines', 'intersections'},
  LFO_NUM = 2,
  GRID_LEVELS = {DIM = 2, LOW_MED = 5, MED = 9, HIGH = 15},
  INTERSECT_OP_NONE = NONE,
  INTERSECT_OP_OCTAVE = OCTAVE,
  INTERSECT_OP_MUTE = MUTE,
  INTERSECT_OP_RESET_SELF = RESET_SELF,
  INTERSECT_OP_RESET_OTHER = RESET_OTHER,
  INTERSECT_OP_RESET_ALL = RESET_ALL,
  INTERSECT_OPS = {NONE, OCTAVE, MUTE, RESET_SELF, RESET_OTHER, RESET_ALL},
  HARMONIC_ACTIONS = {'none', 'octave up', 'octave down', 'fifth', 'triad', 'seventh'},
  TRIAD_TYPES = {'major', 'minor', 'diminished', 'sus4'},
  TRIAD_INTERVALS = {{0,4,7}, {0,3,7}, {0,3,6}, {0,5,7}},
  SEVENTH_TYPES = {'maj7', 'min7', 'dominant 7'},
  SEVENTH_INTERVALS = {{0,4,7,11}, {0,3,7,10}, {0,4,7,10}},
  RHYTHM_ACTIONS = {'none', 'mute', 'retrigger', 'reverse', 'reset self', 'reset others', 'reset all'},
  DIRECTIONS = {FORWARD, REVERSE, PENDULUM, RANDOM},
  DIRECTION_FORWARD = 1,
  DIRECTION_REVERSE = 2,
  DIRECTION_PENDULUM = 3,
  DIRECTION_RANDOM = 4,
  -- The clock runs at twice the legacy base pulse. Index 2 is therefore x1.
  RATE_LABELS = {'x2', 'x1', '/2', '/3', '/4', '/6', '/8', '/5', '/7'},
  GRID_RATE_COUNT = 7,
  RATE_TICK_DIVS = {1, 2, 4, 6, 8, 12, 16, 10, 14},
  RATE_DEFAULT = 2,
  OUTPUT_AUDIO = AUDIO,
  OUTPUT_MIDI = MIDI,
  OUTPUT_AUDIO_MIDI = AUDIO_MIDI,
  OUTPUT_CROW_II_JF = CROW_II_JF,
  OUTPUT_CROW_CV = CROW_CV,
  OUTPUT_CROW_CV_JF = CROW_CV_JF,
  OUTPUT_AUDIO_CV_JF = AUDIO_CV_JF,
  OUTPUT_CROW_II_SC = CROW_II_SC,
  OUTPUTS = {AUDIO, MIDI, AUDIO_MIDI, CROW_II_JF, CROW_CV, CROW_CV_JF, AUDIO_CV_JF, CROW_II_SC},
  EVENT_PATTERN = 'pattern',
  EVENT_SNAPSHOT = 'snapshot'
}

return constants
