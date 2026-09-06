use zbus::interface;

pub const BUS_NAME: &str = "io.mozais.Greeter";
pub const OBJECT_PATH: &str = "/io/mozais/Greeter";

#[derive(Debug, Default)]
pub struct GreeterService;

#[interface(name = "io.mozais.Greeter1")]
impl GreeterService {
    async fn get_state(&self) -> (String, String) {
        ("Idle".to_owned(), String::new())
    }
}
