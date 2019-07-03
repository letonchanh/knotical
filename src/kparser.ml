open Token
open Camlp4
open Debug
open Globals
open Iast
open Formula
open Lib

module Lex = Klexer.Make (Token)
(* module Gram = Camlp4.Struct.Grammar.Static.Make (Lex) *)
module Gram = Camlp4.PreCast.MakeGram (Lex)

(* compute the position by adding the location return by camlp4 *)
let get_pos l =
  let sp = Camlp4.PreCast.Loc.start_pos l in
  let ep = Camlp4.PreCast.Loc.stop_pos l in
  { pos_begin = sp;
    pos_end = ep; }

(* lookahead *)
let peek_bvar =
  Gram.Entry.of_parser "peek_bvar"
    (fun stream ->
       match Stream.npeek 2 stream with
       | [ID _,_; EQ,_]
       | [ID _,_; NE,_]
       | [ID _,_; LT,_]
       | [ID _,_; LE,_]
       | [ID _,_; GT,_]
       | [ID _,_; GE,_]
       | [ID _,_; PLUS,_]
       | [ID _,_; MINUS,_]
       | [ID _,_; MULT,_]
       | [ID _,_; DIV,_]
       | [ID _,_; MOD,_] -> raise Stream.Failure
       | _ -> ())

let program = Gram.Entry.mk "program" ;;

let prop = Gram.Entry.mk "prop" ;;

EXTEND Gram
  GLOBAL: program prop;

  prop:
    [[ e = kat_expr; `EOF -> e ]];

  program:
    [[ procs = LIST0 proc_decl; `EOF ->
       mk_prog procs
     ]];

  proc_decl:
    [[ proc = proc_sig; body = OPT block_stmt ->
       { proc with proc_body = body }
     ]];

  proc_sig:
    [[ t = typ; `ID id; `OPAREN; params = param_list; `CPAREN ->
       mk_proc t id params None (get_pos _loc)
     ]];

  param_list:
    [[ params = LIST0 param SEP `COMMA -> params ]];

  param:
    [[ t = typ; `ID id ->
       mk_param t id (get_pos _loc)
     ]];

  block_stmt:
    [[ `OBRACE; ss = seq_stmt; `CBRACE ->
       Block {
         stmt_block_body = ss;
         stmt_block_local_vars = [];
         stmt_block_pos = get_pos _loc; }
     ]];

  seq_stmt:
    [[ s = single_stmt -> s
     | s = single_stmt; ss = SELF ->
       Seq {
         stmt_seq_fst = s;
         stmt_seq_snd = ss;
         stmt_seq_pos = get_pos _loc; }
     ]];

  single_stmt:
    [[ s = var_decl_stmt; `SEMICOLON -> s
     | s = labeled_stmt -> s
     ]];

  var_decl_stmt:
    [[ t = typ; vs = LIST1 var_decl SEP `COMMA ->
       VarDecl {
         stmt_var_decl_type = t;
         stmt_var_decl_lst = vs;
         stmt_var_decl_pos = get_pos _loc; }
     ]];

  var_decl:
    [[ `ID id; iv = OPT var_init -> (id, iv, get_pos _loc)
     ]];

  var_init:
    [[ `EQ; i = stmt_expr -> i ]];

  labeled_stmt:
    [[ `ID id; `COLON; s = stmt ->
       Label {
         stmt_label_name = id;
         stmt_label_stmt = s;
         stmt_label_pos = get_pos _loc; }
     | s = stmt -> s
     ]];

  stmt:
    [
      [ s = block_stmt -> s ]
    | [ s = selection_stmt -> s
      | s = iteration_stmt -> s
      | s = atomic_stmt; `SEMICOLON -> s
      ]
    ];

atomic_stmt:
  [[ s = assert_stmt -> s
   | s = expression_stmt -> s
   | s = jump_stmt -> s
   | s = skip_stmt -> s
   ]];

  selection_stmt:
    [[ s = if_stmt -> s ]];

  if_stmt:
    [[ `CIF; `OPAREN; c = stmt_expr; `CPAREN; sthen = stmt; selse_opt = OPT else_stmt ->
       let selse = match selse_opt with
         | None -> Skip { stmt_skip_pos = get_pos _loc }
         | Some s -> s in
       Cond {
         stmt_cond_condition = c;
         stmt_cond_then = sthen;
         stmt_cond_else = selse;
         stmt_cond_pos = get_pos (Camlp4.PreCast.Loc.shift 1 _loc); }
     ]];

  else_stmt:
    [[ `CELSE; s = stmt -> s ]];

  iteration_stmt:
    [[ s = while_stmt -> s ]];

  while_stmt:
    [[ `WHILE; `OPAREN; c = stmt_expr; `CPAREN; s = stmt ->
       While {
         stmt_while_condition = c;
         stmt_while_body = s;
         stmt_while_pos = get_pos _loc; }
     ]];

  assert_stmt:
    [[ `ASSERT; `OPAREN; c = logical_formula; `CPAREN ->
       Assert {
         stmt_assert_assume_condition = c;
         stmt_assert_assume_pos = get_pos _loc; }
     | `ASSUME; `OPAREN; c = logical_formula; `CPAREN ->
       Assume {
         stmt_assert_assume_condition = c;
         stmt_assert_assume_pos = get_pos _loc; }
     ]];

  expression_stmt:
    [
      [ s = call_expr -> s ]
    | [ s = assign_expr -> s ] 
    ];

  assign_expr:
    [[ `ID id; op = assign_op; e = stmt_expr ->
       Assign {
         stmt_assign_op = op;
         stmt_assign_left = id;
         stmt_assign_right = e;
         stmt_assign_pos = get_pos _loc; }
     ]];

  assign_op:
    [[ `EQ -> OpAssign
     | `PLUS_ASSIGN -> OpPlusAssign
     | `MINUS_ASSIGN -> OpMinusAssign
     | `MULT_ASSIGN -> OpMultAssign
     | `DIV_ASSIGN -> OpDivAssign
     | `MOD_ASSIGN -> OpModAssign
     ]];

  jump_stmt:
    [[ `BREAK -> Break { stmt_break_pos = get_pos _loc }
     | `CONTINUE -> Continue { stmt_continue_pos = get_pos _loc }
     | `RETURN; v = OPT stmt_expr ->
       Return {
         stmt_return_val = v;
         stmt_return_pos = get_pos _loc; }
     | `GOTO; `ID id ->
       Goto {
         stmt_goto_label = id;
         stmt_goto_pos = get_pos _loc; }
     ]];

  skip_stmt:
    [[ `SKIP -> Skip { stmt_skip_pos = get_pos _loc } ]];

  opt_arg_lst:
    [[ args = LIST0 stmt_expr SEP `COMMA -> args ]];

  call_expr:
    [[ `ID id; `OPAREN; args = opt_arg_lst; `CPAREN ->
       Call {
         stmt_call_method = id;
         stmt_call_args = args;
         stmt_call_pos = get_pos _loc; }
     ]];

  stmt_expr:
    [ "disj_expr"
        [ e1 = SELF; `OROR; e2 = SELF ->
          mk_binary OpLogicalOr e1 e2 (get_pos _loc) ]
    | "conj_expr"
        [ e1 = SELF; `ANDAND; e2 = SELF ->
          mk_binary OpLogicalAnd e1 e2 (get_pos _loc) ]
    | "neg_expr"
        [ `NOT; e = SELF ->
          mk_unary OpLogicalNot e (get_pos _loc) ]
    | "eq_expr"
        [ e1 = SELF; `EQEQ; e2 = SELF ->
          mk_binary OpEq e1 e2 (get_pos _loc)
        | e1 = SELF; `NE; e2 = SELF ->
          mk_binary OpNe e1 e2 (get_pos _loc) ]
    | "rel_expr"
        [ e1 = SELF; `LT; e2 = SELF ->
          mk_binary OpLt e1 e2 (get_pos _loc)
        | e1 = SELF; `LE; e2 = SELF ->
          mk_binary OpLe e1 e2 (get_pos _loc)
        | e1 = SELF; `GT; e2 = SELF ->
          mk_binary OpGt e1 e2 (get_pos _loc)
        | e1 = SELF; `GE; e2 = SELF ->
          mk_binary OpGe e1 e2 (get_pos _loc) ]
    | "add_expr"
        [ e1 = SELF; `PLUS; e2 = SELF ->
          mk_binary OpPlus e1 e2 (get_pos _loc)
        | e1 = SELF; `MINUS; e2 = SELF ->
          mk_binary OpMinus e1 e2 (get_pos _loc) ]
    | "mult_expr"
        [ e1 = SELF; `MULT; e2 = SELF ->
          mk_binary OpMult e1 e2 (get_pos _loc)
        | e1 = SELF; `DIV; e2 = SELF ->
          mk_binary OpDiv e1 e2 (get_pos _loc)
        | e1 = SELF; `MOD; e2 = SELF ->
          mk_binary OpMod e1 e2 (get_pos _loc) ]
    | "unary_expr"
        [ `MINUS; e = SELF ->
          let loc = get_pos _loc in
          let zero = mk_int_lit 0 loc in
          mk_binary OpMinus zero e loc
        | `PLUS; e = SELF -> e ]
    | [ e = call_expr -> e ]
    | "literal"
        [ v = bool_literal -> mk_bool_lit v (get_pos _loc)
        | v = int_literal -> mk_int_lit v (get_pos _loc)
        | v = float_literal -> mk_float_lit v (get_pos _loc)
        | `ID id -> mk_var id (get_pos _loc)
        | `OPAREN; e = SELF; `CPAREN -> e ]
    ];

  logical_formula:
    [ "disj_formula"
        [ f1 = SELF; `OR; f2 = SELF ->
          Disj(f1, f2, (get_pos _loc)) ]
    | "conj_formula"
        [ f1 = SELF; `AND; f2 = SELF ->
          Conj(f1, f2, (get_pos _loc)) ]
    | "neg_formula"
        [ `NOT; f = SELF ->
          Neg(f, (get_pos _loc)) ]
    | "atom_formula"
        [ f = atom_formula -> f
        | `OPAREN; f = SELF; `CPAREN -> f ]
    ];

  atom_formula:
    [[ v = bool_literal -> mk_bconst v (get_pos _loc)
     | peek_bvar; `ID id -> mk_bvar (id, TBool) (get_pos _loc)
     | e1 = arith_expr; op = arith_bin_rel; e2 = arith_expr ->
       mk_bin_rel op e1 e2 (get_pos _loc)
     ]];

  arith_bin_rel:
    [[ `EQ -> Eq
     | `NE -> Ne
     | `LT -> Lt
     | `LE -> Le
     | `GT -> Gt
     | `GE -> Ge
     ]];

  arith_expr:
    [ "add_expr"
        [ e1 = SELF; `PLUS; e2 = SELF ->
          mk_bin_exp Add e1 e2 (get_pos _loc)
        | e1 = SELF; `MINUS; e2 = SELF ->
          mk_bin_exp Sub e1 e2 (get_pos _loc) ]
    | "mult_expr"
        [ e1 = SELF; `MULT; e2 = SELF ->
          mk_bin_exp Mul e1 e2 (get_pos _loc)
        | e1 = SELF; `DIV; e2 = SELF ->
          mk_bin_exp Div e1 e2 (get_pos _loc)
        | e1 = SELF; `MOD; e2 = SELF ->
          mk_bin_exp Mod e1 e2 (get_pos _loc) ]
    | "unary_expr"
        [ `MINUS; e = SELF ->
          let loc = get_pos _loc in
          let zero = mk_iconst 0 loc in
          mk_bin_exp Sub zero e loc
        | `PLUS; e = SELF -> e ]
    | "arith_literal"
        [ v = int_literal -> mk_iconst v (get_pos _loc)
        | v = float_literal -> mk_fconst v (get_pos _loc)
        | `ID id -> mk_evar (id, TInt) (get_pos _loc)
        | `OPAREN; e = SELF; `CPAREN -> e ]
    ];

  bool_literal:
    [[ `TRUE -> true
     | `FALSE -> false
     ]];

  int_literal:
    [[ `INT_LIT (v, _) -> v ]];

  float_literal:
    [[ `FLOAT_LIT (v, _) -> v ]];

  typ:
    [[ `VOID -> TVoid
     | `INT -> TInt
     | `FLOAT -> TFloat
     | `BOOL -> TBool
     ]];

  kat_expr:
    [[ e = kat_pls_expr -> e ]];

  kat_pls_expr:
    [[ e1 = kat_pls_expr; `PLUS; e2 = kat_dot_expr -> Pls (e1, e2)
     | e = kat_dot_expr -> e
     ]];

  kat_dot_expr:
    [[ e1 = kat_dot_expr; `DOT; e2 = kat_str_expr -> Dot (e1, e2)
     | e = kat_str_expr -> e
     ]];

  kat_str_expr:
    [[ e = kat_atom_expr; `MULT -> Str e
     | e = kat_atom_expr -> e
     ]];

  kat_atom_expr:
    [[ `TOP -> Tst Top
     | `BOT -> Tst Bot
     | `OSQUARE; s = logical_formula; `CSQUARE -> Tst (Prd s)
     | `NOT; t = kat_atom_test -> Tst (Neg t)
     | `OBRACE; s = atomic_stmt; `CBRACE -> KVar s
     | `OPAREN; e = kat_expr; `CPAREN -> e
     | `ANY -> Any
     ]];

  kat_test:
    [[ e = kat_dsj_test -> e ]];

  kat_dsj_test:
    [[ e1 = kat_dsj_test; `PLUS; e2 = kat_cnj_test -> Dsj (e1, e2)
     | e = kat_cnj_test -> e
     ]];

  kat_cnj_test:
    [[ e1 = kat_cnj_test; `DOT; e2 = kat_atom_test -> Cnj (e1, e2)
     | e = kat_atom_test -> e
     ]];

  kat_atom_test:
    [[ `TOP -> Top
     | `BOT -> Bot
     | `OSQUARE; s = logical_formula; `CSQUARE -> Prd s
     | `NOT; t = kat_atom_test -> Neg t
     | `OPAREN; e = kat_test; `CPAREN -> e
     ]];

  (* kat_expr:
   *   [ "pls_expr"
   *       [ e1 = SELF; `PLUS; e2 = SELF -> Pls (e1, e2) ]
   *   | "dot_expr"
   *       [ e1 = SELF; `DOT; e2 = SELF -> Dot (e1, e2) ]
   *   | "str_expr"
   *       [ e = SELF; `STAR -> Str e ]
   *   | "atom_expr"
   *       [ `TOP -> Tst Top
   *       | `BOT -> Tst Bot
   *       | `OSQUARE; s = logical_formula; `CSQUARE -> Tst (Prd s)
   *       | `NOT; t = kat_test -> Tst (Neg t) 
   *       | `OBRACE; s = atomic_stmt; `CBRACE -> KVar s
   *       | `OPAREN; e = SELF; `CPAREN -> e ]
   *   ];
   * 
   *  kat_test:
   *   [ "dsj_test"
   *       [ e1 = SELF; `OR; e2 = SELF -> Dsj (e1, e2) ]
   *   | "cnj_test"
   *       [ e1 = SELF; `AND; e2 = SELF -> Cnj (e1, e2)
   *       | e1 = SELF; e2 = SELF -> Cnj (e1, e2) ]
   *   | "neg_test"
   *       [ `NOT; e = SELF -> Neg e ]
   *   | "atom_test"
   *       [ `OSQUARE; s = logical_formula; `CSQUARE -> Prd s
   *       | `TOP -> Top
   *       | `BOT -> Bot
   *       | `OPAREN; e = SELF; `CPAREN -> e ]
   *   ]; *)
END;;

(* parsing commands *)

let parse_prop prop_str =
  try
    (* let inchan = open_in !file_kat_prop in
     * let kexpr = Gram.parse prop (PreCast.Loc.mk "prop") (Stream.of_channel inchan) in *)
    let kexpr = Gram.parse_string prop (PreCast.Loc.mk "prop") !raw_kat_prop in
    kexpr
  with
  | Lex.Loc.Exc_located (l, t) ->
    let pos = get_pos l in
    let filename = pos.pos_begin.Lexing.pos_fname in
    let location = pr_pos pos in
    let spos = "Location: File: " ^ filename ^ ". Line/Column: " ^ location in
    let msg = "Message: " ^ (pr_exn t) in
    error ("Syntax error!\n" ^ msg ^ "\n" ^ spos)
  | e -> raise e

let parse_program name body =
  try
    let prog = Gram.parse program (PreCast.Loc.mk name) body in
    { prog with prog_file = name }
  with
  | Lex.Loc.Exc_located (l, t) ->
    let pos = get_pos l in
    let filename = pos.pos_begin.Lexing.pos_fname in
    let location = pr_pos pos in
    let spos = "Location: File: " ^ filename ^ ". Line/Column: " ^ location in
    let msg = "Message: " ^ (pr_exn t) in
    error ("Syntax error!\n" ^ msg ^ "\n" ^ spos)
  | e -> raise e

let parse_one_file (file: string): prog_decl =
  let () = input_file_name := file in
  let inchan =
    try open_in file
    with e -> error ("Unable to open file: " ^ file) in
  let iprog =
    try parse_program file (Stream.of_channel inchan)
    with
    | Not_found -> error ("File not found: " ^ file)
    | End_of_file -> error ("Unable to parse file: " ^ file)
    | Lex.Loc.Exc_located (l, t) -> raise t in
  let () = close_in inchan in
  let () = if !print_prog_iast then (
      let program =
        "============================================\n" ^
        "=========      Parsed Program      =========\n" ^
        "============================================\n\n" ^
        (pr_prog ~pr_paren:true iprog) ^ "\n\n" in
      print_endline program) in

  (* let cfg_prog = I.trans_cfg_prog_decl iprog in
   * let flatten_cfg_prog = I.flatten_prog_decl cfg_prog in
   * let () = if !print_prog_iast then (
   *   let program =
   *     "=============================================\n" ^
   *     "=========      Flatten Program      =========\n" ^
   *     "=============================================\n\n" ^
   *     (String.concat "\n\n"
   *        (List.map (fun (name, stmt_lst) ->
   *             name ^ "\n\t" ^
   *             (String.concat "\n\t" (List.map I.pr_stmt stmt_lst))
   *           ) flatten_cfg_prog)) ^ "\n\n" in
   *   print_endline program) in
   * let cfg_lst = List.map (fun (name, stmt_lst) ->
   *     (name, Cfg.trans_cfg stmt_lst)) flatten_cfg_prog in
   * let () = if !print_prog_iast then (
   *   let program =
   *     "=================================\n" ^
   *     "=========      CFG      =========\n" ^
   *     "=================================\n\n" ^
   *     (String.concat "\n\n"
   *        (List.map (fun (name, cfg) ->
   *             name ^ "\n\t" ^ (Cfg.CFG.print cfg)
   *           ) cfg_lst)) ^ "\n\n" in
   *   print_endline program) in
   * let kat1s = List.map (fun (name, cfg) ->
   *     KI.kat_interp (Iface.mk_true ()) cfg) cfg_lst in *)
  iprog
