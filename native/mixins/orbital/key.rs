fn orbital_key(game: &mut crate::game::Game<'_>, key: &str, pressed: bool) {
    crate::game::orbital_glue::key(game, key, pressed);
}
