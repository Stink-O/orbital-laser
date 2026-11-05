fn orbital_net_from_server(game: &mut crate::game::Game<'_>, channel: &str, data: &[u8]) {
    crate::game::orbital_glue::from_server(game, channel, data);
}
