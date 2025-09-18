use std::net::TcpListener;
use zero2prod::startup::run;

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    println!("Zero2prod starting...");
    let listener = TcpListener::bind("127.0.0.1:0").expect("Failed to bind random port");
    run(listener)?.await
}
