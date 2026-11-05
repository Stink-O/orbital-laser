fn orbital_screen_key(
    game: &crate::game::Game<'_>,
    screen: &crate::game::native_hooks::NativeScreenView<'_>,
    key: &str,
    canceled: &mut bool,
) {
    crate::game::orbital_glue::screen_key(game, screen, key, canceled);
}
