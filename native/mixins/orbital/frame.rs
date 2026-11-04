fn orbital_frame(game: &mut crate::game::Game<'_>, elapsed: std::time::Duration) {
    crate::game::orbital_glue::frame(game, elapsed);
}
