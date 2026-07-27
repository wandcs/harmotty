#[derive(Default)]
pub struct Utf8StreamDecoder {
    pending: Vec<u8>,
}

impl Utf8StreamDecoder {
    pub fn push(&mut self, data: &[u8]) -> String {
        self.pending.extend_from_slice(data);
        let mut output = String::new();
        let mut offset = 0;

        while offset < self.pending.len() {
            match std::str::from_utf8(&self.pending[offset..]) {
                Ok(valid) => {
                    output.push_str(valid);
                    offset = self.pending.len();
                }
                Err(error) => {
                    let valid_len = error.valid_up_to();
                    if valid_len > 0 {
                        if let Ok(valid) =
                            std::str::from_utf8(&self.pending[offset..offset + valid_len])
                        {
                            output.push_str(valid);
                        }
                        offset += valid_len;
                    }
                    match error.error_len() {
                        Some(invalid_len) => {
                            output.push('\u{FFFD}');
                            offset += invalid_len;
                        }
                        None => break,
                    }
                }
            }
        }

        if offset > 0 {
            self.pending.drain(..offset);
        }
        output
    }

    pub fn finish(&mut self) -> String {
        if self.pending.is_empty() {
            return String::new();
        }
        let output = String::from_utf8_lossy(&self.pending).to_string();
        self.pending.clear();
        output
    }
}

#[cfg(test)]
mod tests {
    use super::Utf8StreamDecoder;

    #[test]
    fn decodes_utf8_split_at_every_byte_boundary() {
        let text = "LeanTTY 中文终端";
        let bytes = text.as_bytes();

        for split in 0..=bytes.len() {
            let mut decoder = Utf8StreamDecoder::default();
            let mut output = decoder.push(&bytes[..split]);
            output.push_str(&decoder.push(&bytes[split..]));
            output.push_str(&decoder.finish());
            assert_eq!(output, text, "split={split}");
        }
    }

    #[test]
    fn replaces_invalid_utf8_without_losing_following_text() {
        let mut decoder = Utf8StreamDecoder::default();
        let output = decoder.push(&[b'a', 0xff, b'b']);
        assert_eq!(output, "a\u{FFFD}b");
    }

    #[test]
    fn handles_tui_escape_sequence_burst() {
        let mut decoder = Utf8StreamDecoder::default();

        let helix_start: &[u8] = b"\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H\x1b[38;2;205;214;244m  _   _      _ _\x1b[0m\r\n\x1b[38;2;137;180;250m | |_| | ___| (_)_____  __\x1b[0m\r\n";
        let more: &[u8] = b"\x1b[38;2;166;227;161mWelcome to helix\x1b[0m\r\n\x1b[?25h";
        let output1 = decoder.push(helix_start);
        let output2 = decoder.push(more);
        let final_bytes = decoder.finish();
        let full = format!("{}{}{}", output1, output2, final_bytes);
        assert!(full.contains("_   _      _ _"));
        assert!(full.contains("Welcome to helix"));
        assert!(
            !full.contains("\u{FFFD}"),
            "should not produce replacement chars: {}",
            full
        );
    }

    #[test]
    fn preserves_bytes_across_packet_boundaries_in_escape_sequences() {
        let csi = b"\x1b[38;2;137;180;250m";
        for split in 1..csi.len() - 1 {
            let mut d = Utf8StreamDecoder::default();
            let first = d.push(&csi[..split]);
            let second = d.push(&csi[split..]);
            let fin = d.finish();
            assert!(
                !first.contains('\u{FFFD}')
                    && !second.contains('\u{FFFD}')
                    && !fin.contains('\u{FFFD}'),
                "split at {} produced replacement chars",
                split
            );
        }
    }

    #[test]
    fn handles_10kb_multiline_tui_redraw() {
        let mut decoder = Utf8StreamDecoder::default();
        let mut line: String = String::new();
        for i in 0..200 {
            line.push_str(&format!(
                "\x1b[38;2;{};{};{}m",
                137 + (i % 10) * 10,
                180,
                250
            ));
            line.push_str("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
            line.push_str("\x1b[0m\r\n");
        }
        let bytes = line.as_bytes();
        let chunk = 37;

        let mut total: String = String::new();
        let mut pos: usize = 0;
        while pos < bytes.len() {
            let end: usize = (pos + chunk).min(bytes.len());
            total.push_str(&decoder.push(&bytes[pos..end]));
            pos = end;
        }
        total.push_str(&decoder.finish());

        assert!(total.len() > 10_000);
        assert!(!total.contains('\u{FFFD}'));
        assert!(total.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ"));
    }
}
