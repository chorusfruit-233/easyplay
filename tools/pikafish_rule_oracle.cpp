// GPL-3.0-or-later. Test harness for unmodified pinned Pikafish rule_judge.
#include <deque>
#include <iostream>
#include <sstream>
#include "attacks.h"
#include "position.h"
#include "movegen.h"
using namespace Stockfish;
int main() {
 Attacks::init(); Position::init();
 std::string fen, commands;
 while(std::getline(std::cin, fen) && std::getline(std::cin, commands)) {
  Position p; std::deque<StateInfo> states(1);
  if(p.set(fen, &states.back())) { std::cout << "invalid fen\n"; continue; }
  std::istringstream moves(commands); std::string text; bool valid=true;
  while(moves >> text) {
   Move m=Move(Square((text[1]-'0')*9+text[0]-'a'), Square((text[3]-'0')*9+text[2]-'a'));
   if(!MoveList<LEGAL>(p).contains(m)) { valid=false; break; }
   states.emplace_back();p.do_move(m,states.back(),nullptr);
  }
  Value result;bool end=p.rule_judge(result);
  std::cout << (valid ? "valid" : "invalid") << " " << end << " " << (end?int(result):0) << " " << p.state()->rule60 << "\n";
 }
}
