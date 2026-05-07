// Validate a `track()` payload against a manifest entry's typed schema.
//
// The manifest shape is fixed by `lib/track_relay/manifest.rb` (Plan
// 02-03):
//
//   {
//     "<event_name>": {
//       "params":   {"<param>": "<type>"},  // type ∈ ParamSchema types
//       "required": ["<param>", ...]
//     }
//   }
//
// Param types mirror the Ruby `ParamSchema` types:
//   integer, string, float, boolean, datetime
//
// Returns an array of human-readable error messages (empty when the
// payload is valid). Extra params not declared in `schema.params` are
// allowed silently — the catalog is opt-in for typing, not gate-keeping.

const TYPE_CHECKS = {
  integer(value) {
    return typeof value === "number" && Number.isFinite(value) && Number.isInteger(value);
  },
  float(value) {
    return typeof value === "number" && Number.isFinite(value);
  },
  string(value) {
    return typeof value === "string";
  },
  boolean(value) {
    return typeof value === "boolean";
  },
  datetime(value) {
    if (value instanceof Date) return !Number.isNaN(value.getTime());
    if (typeof value !== "string") return false;
    const parsed = Date.parse(value);
    return !Number.isNaN(parsed);
  }
};

/**
 * @param {string} eventName
 * @param {{params: Record<string,string>, required: string[]}} schema
 * @param {Record<string, unknown>} params
 * @returns {string[]} validation errors (empty when valid)
 */
export function validateParams(eventName, schema, params) {
  const errors = [];
  const declared = schema.params || {};
  const required = schema.required || [];

  for (const key of required) {
    if (params[key] == null) {
      errors.push(`${eventName}: missing required param "${key}"`);
    }
  }

  for (const [key, value] of Object.entries(params)) {
    const expectedType = declared[key];
    if (!expectedType) continue;          // extra params allowed
    if (value == null) continue;          // missing-required already reported above
    const check = TYPE_CHECKS[expectedType];
    if (!check) continue;                 // unknown type in manifest — be permissive
    if (!check(value)) {
      errors.push(
        `${eventName}: param "${key}" expected ${expectedType}, got ${describe(value)}`
      );
    }
  }

  return errors;
}

function describe(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}
