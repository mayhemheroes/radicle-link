#![no_main]
use libfuzzer_sys::fuzz_target;
use std::str::FromStr;

fuzz_target!(|data: &str| {
    _ = link_canonical::json::Value::from_str(data);
});
