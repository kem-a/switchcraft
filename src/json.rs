// JSON through serde_json, with two json-glib habits kept: the data ends at
// the first NUL, and a blank document is no error, just no root.

use serde_json::Value;

pub fn parse(data: &[u8]) -> Result<Option<Value>, String> {
    let end = data.iter().position(|b| *b == 0).unwrap_or(data.len());
    let data = &data[..end];
    if data
        .iter()
        .all(|b| matches!(b, b' ' | b'\t' | b'\n' | b'\r'))
    {
        return Ok(None);
    }
    serde_json::from_slice(data)
        .map(Some)
        .map_err(|e| e.to_string())
}

// The string, or None for any other type. It ends at the first NUL like the
// C strings json-glib returned, so no NUL reaches GLib or GTK.
pub fn string(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(|s| s.split('\0').next().unwrap_or_default().to_owned())
}

pub fn pretty(object: serde_json::Map<String, Value>) -> String {
    format!("{:#}", Value::Object(object))
}
