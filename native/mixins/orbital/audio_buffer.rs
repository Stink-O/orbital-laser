// The output's buffer at the ALSA default (about 100 ms, as the fork plays) instead of upstream's short fixed 1024 frames,
// unless HORIZON_AUDIO_BUFFER says otherwise. With the short one a heavy strike's stalled frames ran the device dry,
// ALSA answered POLLERR for good, and every sound stopped until the game was restarted (upstream reopens the output only
// when the device is gone).
#[cfg(feature = "audio")]
fn orbital_audio_buffer(sc: cpal::StreamConfig) -> cpal::StreamConfig {
    let mut sc = sc;
    if std::env::var_os("HORIZON_AUDIO_BUFFER").is_none() {
        sc.buffer_size = cpal::BufferSize::Default;
    }
    sc
}
