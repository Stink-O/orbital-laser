fn orbital_tick(game: &mut crate::game::Game<'_>) {
    crate::game::orbital_glue::tick(game);
}
