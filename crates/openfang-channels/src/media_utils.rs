use std::time::Duration;
use tracing::{info, warn};

/// Recognize image content via Gemini Vision. Returns text description or bracketed error.
pub async fn recognize_image(
    client: &reqwest::Client,
    image_data: &[u8],
    prompt: &str,
) -> String {
    let gemini_key = match std::env::var("GEMINI_API_KEY") {
        Ok(k) => k,
        Err(_) => {
            warn!("GEMINI_API_KEY not set, cannot recognize image");
            return "[Image recognition unavailable: GEMINI_API_KEY not configured]".into();
        }
    };

    let mime = detect_image_mime(image_data);
    let b64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, image_data);
    let prompt = if prompt.is_empty() { "Describe this image in detail." } else { prompt };

    let model = std::env::var("VISION_MODEL").unwrap_or_else(|_| "gemini-2.5-flash".into());
    let url = format!(
        "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={gemini_key}"
    );

    let payload = serde_json::json!({
        "contents": [{"parts": [
            {"text": prompt},
            {"inline_data": {"mime_type": mime, "data": b64}}
        ]}],
        "generationConfig": {"temperature": 0.4, "maxOutputTokens": 2048}
    });

    let resp = match client
        .post(&url)
        .json(&payload)
        .timeout(Duration::from_secs(60))
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => return format!("[Image recognition failed: {e}]"),
    };

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        warn!("Gemini Vision error [{status}]: {}", &body[..body.len().min(200)]);
        return format!("[Image recognition failed: HTTP {status}]");
    }

    match resp.json::<serde_json::Value>().await {
        Ok(result) => {
            let text: String = result["candidates"]
                .as_array()
                .and_then(|c| c.first())
                .and_then(|c| c["content"]["parts"].as_array())
                .map(|parts| {
                    parts.iter().filter_map(|p| p["text"].as_str()).collect::<Vec<_>>().join(" ")
                })
                .unwrap_or_default();

            if text.is_empty() {
                "[Image recognition returned no result]".into()
            } else {
                text
            }
        }
        Err(e) => format!("[Image recognition parse error: {e}]"),
    }
}

pub async fn download_url(client: &reqwest::Client, url: &str) -> Option<Vec<u8>> {
    let bytes = client
        .get(url)
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .ok()?
        .bytes()
        .await
        .ok()?;
    Some(bytes.to_vec())
}

fn detect_image_mime(data: &[u8]) -> &'static str {
    if data.starts_with(b"\x89PNG") {
        "image/png"
    } else if data.starts_with(b"\xFF\xD8\xFF") {
        "image/jpeg"
    } else if data.starts_with(b"GIF8") {
        "image/gif"
    } else if data.len() >= 12 && &data[8..12] == b"WEBP" {
        "image/webp"
    } else if data.starts_with(b"BM") {
        "image/bmp"
    } else {
        "image/jpeg"
    }
}

/// Transcribe audio via Groq Whisper (primary) or OpenAI Whisper (fallback).
pub async fn transcribe_audio(
    client: &reqwest::Client,
    audio_bytes: &[u8],
    filename: &str,
) -> Option<String> {
    let (mime, upload_filename) = if filename.ends_with(".oga") || filename.ends_with(".ogg") {
        ("audio/ogg", filename.replace(".oga", ".ogg"))
    } else if filename.ends_with(".mp3") {
        ("audio/mpeg", filename.to_string())
    } else if filename.ends_with(".wav") {
        ("audio/wav", filename.to_string())
    } else if filename.ends_with(".m4a") {
        ("audio/mp4", filename.to_string())
    } else {
        ("audio/ogg", format!("{filename}.ogg"))
    };

    if let Ok(key) = std::env::var("GROQ_API_KEY") {
        if let Some(text) = whisper_transcribe(
            client, audio_bytes, &upload_filename, mime, &key,
            "https://api.groq.com/openai/v1/audio/transcriptions",
            "whisper-large-v3-turbo",
        ).await {
            return Some(text);
        }
    }

    if let Ok(key) = std::env::var("OPENAI_API_KEY") {
        if let Some(text) = whisper_transcribe(
            client, audio_bytes, &upload_filename, mime, &key,
            "https://api.openai.com/v1/audio/transcriptions",
            "whisper-1",
        ).await {
            return Some(text);
        }
    }

    warn!("Voice transcription failed for '{filename}' ({} bytes)", audio_bytes.len());
    None
}

async fn whisper_transcribe(
    client: &reqwest::Client,
    audio_bytes: &[u8],
    filename: &str,
    mime: &str,
    api_key: &str,
    url: &str,
    model: &str,
) -> Option<String> {
    let file_part = reqwest::multipart::Part::bytes(audio_bytes.to_vec())
        .file_name(filename.to_string())
        .mime_str(mime)
        .ok()?;

    let form = reqwest::multipart::Form::new()
        .part("file", file_part)
        .text("model", model.to_string())
        .text("response_format", "json");

    let resp = client
        .post(url)
        .bearer_auth(api_key)
        .multipart(form)
        .timeout(Duration::from_secs(60))
        .send()
        .await
        .ok()?;

    let status = resp.status();
    let result: serde_json::Value = resp.json().await.ok()?;
    let text = result["text"].as_str()?;
    if text.is_empty() {
        warn!("Whisper ({model}): empty transcription (status={status})");
        return None;
    }
    info!("Transcribed audio via {model}: {} chars", text.len());
    Some(text.to_string())
}
