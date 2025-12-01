#include <iostream>
#include <fmt/chrono.h>

int main(int argc, const char *argv[]) {
  auto now = std::chrono::system_clock::now();
  fmt::print("Date and time: {}\n", now);
  fmt::print("Time: {:%H:%M}\n", now);
  std::string s = fmt::format("The answer is {}.", 42);
  // s == "The answer is 42."
  fmt::print("{}\n", (s == "The answer is 42."));
  return 0;
}