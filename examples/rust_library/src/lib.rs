// Example library that we want to fuzz
//
// This demonstrates a typical Rust library that might have bugs

/// Custom protocol message format
#[derive(Debug)]
pub struct Message {
    pub version: u8,
    pub msg_type: u8,
    pub length: u16,
    pub payload: Vec<u8>,
}

/// Parse a binary message
///
/// Format:
///   [version: 1 byte][type: 1 byte][length: 2 bytes][payload: N bytes]
pub fn parse_message(data: &[u8]) -> Result<Message, ParseError> {
    if data.len() < 4 {
        return Err(ParseError::TooShort);
    }

    let version = data[0];
    let msg_type = data[1];
    let length = u16::from_be_bytes([data[2], data[3]]);

    // Validate version
    if version != 1 {
        return Err(ParseError::InvalidVersion);
    }

    // Check if we have enough data
    let payload_start = 4;
    let payload_end = payload_start + length as usize;

    if data.len() < payload_end {
        return Err(ParseError::TruncatedPayload);
    }

    let payload = data[payload_start..payload_end].to_vec();

    Ok(Message {
        version,
        msg_type,
        length,
        payload,
    })
}

/// Process a text command
pub fn process_command(cmd: &str) -> Result<String, ParseError> {
    let parts: Vec<&str> = cmd.split_whitespace().collect();

    if parts.is_empty() {
        return Err(ParseError::EmptyCommand);
    }

    match parts[0] {
        "GET" => {
            if parts.len() < 2 {
                return Err(ParseError::MissingArgument);
            }
            Ok(format!("Getting: {}", parts[1]))
        }
        "SET" => {
            if parts.len() < 3 {
                return Err(ParseError::MissingArgument);
            }
            Ok(format!("Setting {} = {}", parts[1], parts[2]))
        }
        "DELETE" => {
            if parts.len() < 2 {
                return Err(ParseError::MissingArgument);
            }
            Ok(format!("Deleting: {}", parts[1]))
        }
        _ => Err(ParseError::UnknownCommand),
    }
}

/// Parse a simple configuration format
///
/// Format: key=value, one per line
pub fn parse_config(config: &str) -> Result<std::collections::HashMap<String, String>, ParseError> {
    let mut map = std::collections::HashMap::new();

    for line in config.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        let parts: Vec<&str> = line.splitn(2, '=').collect();
        if parts.len() != 2 {
            return Err(ParseError::InvalidFormat);
        }

        let key = parts[0].trim();
        let value = parts[1].trim();

        if key.is_empty() {
            return Err(ParseError::EmptyKey);
        }

        map.insert(key.to_string(), value.to_string());
    }

    Ok(map)
}

#[derive(Debug, PartialEq)]
pub enum ParseError {
    TooShort,
    InvalidVersion,
    TruncatedPayload,
    EmptyCommand,
    MissingArgument,
    UnknownCommand,
    InvalidFormat,
    EmptyKey,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_message() {
        let data = vec![1, 2, 0, 5, b'h', b'e', b'l', b'l', b'o'];
        let msg = parse_message(&data).unwrap();
        assert_eq!(msg.version, 1);
        assert_eq!(msg.msg_type, 2);
        assert_eq!(msg.length, 5);
        assert_eq!(msg.payload, b"hello");
    }

    #[test]
    fn test_process_command() {
        assert_eq!(process_command("GET foo").unwrap(), "Getting: foo");
        assert_eq!(
            process_command("SET bar baz").unwrap(),
            "Setting bar = baz"
        );
    }

    #[test]
    fn test_parse_config() {
        let config = "name=value\nkey=data\n# comment\n";
        let map = parse_config(config).unwrap();
        assert_eq!(map.get("name"), Some(&"value".to_string()));
        assert_eq!(map.get("key"), Some(&"data".to_string()));
    }
}
