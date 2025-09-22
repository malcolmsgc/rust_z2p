use crate::routes::{health_check, subscribe};
use actix_web::dev::Server;
use actix_web::{App, HttpServer, web};
use sqlx::PgPool;
use std::net::TcpListener;

pub fn run(listener: TcpListener, dp_pool: PgPool) -> Result<Server, std::io::Error> {
    // web::Data wraps our connection in an Atomic Reference Counted pointer (Arc)
    let dp_pool = web::Data::new(dp_pool);
    let addr = listener.local_addr()?;
    // NB the `move` to capture `connection` in closure scope
    let server = HttpServer::new(move || {
        App::new()
            .route("/health_check", web::get().to(health_check))
            .route("/subscriptions", web::post().to(subscribe))
            // pointer to PgConnection cloned and registered as part of actix_web App state
            .app_data(dp_pool.clone())
    })
    .listen(listener)?
    .run();
    println!("HttpServer started on {}", addr);
    Ok(server)
}
