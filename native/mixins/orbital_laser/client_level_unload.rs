fn orbital_client_level_unload(game: &mut crate::game::Game<'_>, dimension: &str) {
    crate::game::orbital_glue::client_level_unload(game, dimension);
}
