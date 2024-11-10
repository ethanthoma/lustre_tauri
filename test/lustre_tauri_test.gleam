import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// There is no real way to run tests besides packaging a whole tauri app
pub fn hello_world_test() {
  1
  |> should.equal(1)
}
