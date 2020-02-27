let io_buffer_size = 65536
let kstrf k fmt = Format.kasprintf k fmt
let invalid_arg fmt = Format.kasprintf invalid_arg fmt

module Bigarray = Bigarray_compat (* XXX(dinosaure): MirageOS compatibility. *)
type bigstring = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
type window = De.window
type optint = Optint.t

let bigstring_create l = Bigarray.Array1.create Bigarray.char Bigarray.c_layout l
let bigstring_empty = Bigarray.Array1.create Bigarray.char Bigarray.c_layout 0
let bigstring_length x = Bigarray.Array1.dim x [@@inline]

external swap16 : int -> int = "%bswap16"
external swap32 : int32 -> int32 = "caml_int32_bswap"

external unsafe_get_uint8 : bigstring -> int -> int = "%caml_ba_ref_1"
external unsafe_get_char : bigstring -> int -> char = "%caml_ba_ref_1"
external unsafe_get_uint16 : bigstring -> int -> int = "%caml_bigstring_get16"
external unsafe_get_uint32 : bigstring -> int -> int32 = "%caml_bigstring_get32"

external unsafe_set_char : bigstring -> int -> char -> unit = "%caml_ba_set_1"
external unsafe_set_uint8 : bigstring -> int -> int -> unit = "%caml_ba_set_1"
external unsafe_set_uint16 : bigstring -> int -> int -> unit = "%caml_bigstring_set16"
external unsafe_set_uint32 : bigstring -> int -> int32 -> unit = "%caml_bigstring_set32"

let bytes_unsafe_get_uint8 : bytes -> int -> int =
  fun buf off -> Char.code (Bytes.get buf off)

external bytes_unsafe_get_uint32 : bytes -> int -> int32 = "%caml_bytes_get32"

let bytes_unsafe_set_uint8 : bytes -> int -> int -> unit =
  fun buf off v -> Bytes.set buf off (Char.unsafe_chr (v land 0xff))

external bytes_unsafe_set_uint16 : bytes -> int -> int -> unit = "%caml_bytes_set16"
external bytes_unsafe_set_uint32 : bytes -> int -> int32 -> unit = "%caml_bytes_set32"

let string_unsafe_get_uint8 : string -> int -> int =
  fun buf off -> Char.code (String.get buf off)

external string_unsafe_get_uint32 : string -> int -> int32 = "%caml_string_get32"

let input_bigstring ic buf off len =
  let tmp = Bytes.create len in
  let res = input ic tmp 0 len in

  let len0 = res land 3 in
  let len1 = res asr 2 in

  for i = 0 to len1 - 1
  do
    let i = i * 4 in
    let v = bytes_unsafe_get_uint32 tmp i in
    unsafe_set_uint32 buf (off + i) v
  done ;

  for i = 0 to len0 - 1
  do
    let i = len1 * 4 + i in
    let v = bytes_unsafe_get_uint8 tmp i in
    unsafe_set_uint8 buf (off + i) v
  done ; res

let bigstring_to_string v =
  let len = bigstring_length v in
  let res = Bytes.create len in
  let len0 = len land 3 in
  let len1 = len asr 2 in

  for i = 0 to len1 - 1
  do
    let i = i * 4 in
    let v = unsafe_get_uint32 v i in
    bytes_unsafe_set_uint32 res i v
  done ;

  for i = 0 to len0 - 1
  do
    let i = len1 * 4 + i in
    let v = unsafe_get_uint8 v i in
    bytes_unsafe_set_uint8 res i v
  done ;

  Bytes.unsafe_to_string res

let output_bigstring oc buf off len =
  (* XXX(dinosaure): stupidly slow! *)
  let v = Bigarray.Array1.sub buf off len in
  let v = bigstring_to_string v in
  output_string oc v

let bigstring_of_string v =
  let len = String.length v in
  let res = bigstring_create len in
  let len0 = len land 3 in
  let len1 = len asr 2 in

  for i = 0 to len1 - 1
  do
    let i = i * 4 in
    let v = string_unsafe_get_uint32 v i in
    unsafe_set_uint32 res i v
  done ;

  for i = 0 to len0 - 1
  do
    let i = len1 * 4 + i in
    let v = string_unsafe_get_uint8 v i in
    unsafe_set_uint8 res i v
  done ; res

let unsafe_get_uint16_be =
  if Sys.big_endian
  then fun buf off -> unsafe_get_uint16 buf off
  else fun buf off -> swap16 (unsafe_get_uint16 buf off)

let unsafe_set_uint16_be =
  if Sys.big_endian
  then fun buf off v -> unsafe_set_uint16 buf off v
  else fun buf off v -> unsafe_set_uint16 buf off (swap16 v)

let unsafe_get_uint32_be =
  if Sys.big_endian
  then fun buf off -> unsafe_get_uint32 buf off
  else fun buf off -> swap32 (unsafe_get_uint32 buf off)

let unsafe_get_uint32_le =
  if Sys.big_endian
  then fun buf off -> swap32 (unsafe_get_uint32 buf off)
  else fun buf off -> unsafe_get_uint32 buf off

let unsafe_set_uint32_be =
  if Sys.big_endian
  then fun buf off v -> unsafe_set_uint32 buf off v
  else fun buf off v -> unsafe_set_uint32 buf off (swap32 v)

let unsafe_set_uint32_le =
  if Sys.big_endian
  then fun buf off v -> unsafe_set_uint32 buf off (swap32 v)
  else fun buf off v -> unsafe_set_uint32 buf off v

let bytes_unsafe_set_uint16_be =
  if Sys.big_endian
  then fun buf off v -> bytes_unsafe_set_uint16 buf off v
  else fun buf off v -> bytes_unsafe_set_uint16 buf off (swap16 v)

let bytes_unsafe_set_uint32_be =
  if Sys.big_endian
  then fun buf off v -> bytes_unsafe_set_uint32 buf off v
  else fun buf off v -> bytes_unsafe_set_uint32 buf off (swap32 v)

let invalid_bounds off len = invalid_arg "Out of bounds (off: %d, len: %d)" off len

module Inf = struct
  type src = [ `Channel of in_channel | `String of string | `Manual ]

  type decoder =
    { src : De.Inf.src
    ; i : bigstring
    ; i_pos : int
    ; i_len : int
    ; wr : optint
    ; crc : optint
    ; dd : dd
    ; flg : int
    ; cm : int
    ; mtime : int32
    ; xfl : int
    ; os : int
    ; fextra : string option
    ; fname : string option
    ; fcomment : string option
    ; f : bool
    ; t : bigstring
    ; t_need : int
    ; t_len : int
    ; k : decoder -> signal }
  and dd =
    | Dd of { state : De.Inf.decoder
            ; window : De.window
            ; o : De.bigstring }
    | Hd of { o : De.bigstring }
  and signal =
    [ `Await of decoder
    | `Flush of decoder
    | `End of decoder
    | `Malformed of string ]

  let malformedf fmt = kstrf (fun s -> `Malformed s) fmt

  let err_unexpected_end_of_input _ =
    malformedf "Unexpected end of input"

  let err_invalid_checksum expect d =
    malformedf "Invalid checksum (expect:%04lx, has:%04lx)" expect (Optint.to_int32 d.crc)

  let err_invalid_isize expect d =
    malformedf "Invalid input size (expect:%ld, inflated:%ld)" expect (Optint.to_int32 d.wr)

  let err_invalid_header _ =
    malformedf "Invalid header"

  (* remaining bytes to read [d.i]. *)
  let i_rem d = d.i_len - d.i_pos + 1
  [@@inline]

  (* End of input [eoi] is signalled by [d.i_pos = 0] and [d.i_len = min_int]
     which implies [i_rem d < 0] is [true]. *)

  let eoi d =
    { d with i= bigstring_empty
           ; i_pos= 0
           ; i_len= min_int }

  let refill k d = match d.dd, d.src with
    | Dd { state; _ }, `String _ ->
      De.Inf.src state bigstring_empty 0 0 ;
      k (eoi d)
    | Dd { state; _ }, `Channel ic ->
      let res = input_bigstring ic d.i 0 (bigstring_length d.i) in
      De.Inf.src state d.i 0 res ; k d
    | (Dd _ | Hd _), `Manual ->
      `Await { d with k }
    | Hd _, `String _ ->
      k (eoi d)
    | Hd _, `Channel ic ->
      let res = input_bigstring ic d.i 0 (bigstring_length d.i) in
      if res == 0
      then k (eoi d)
      else k { d with i_pos= 0; i_len= res - 1 }

  let flush k d = `Flush { d with k }

  let blit src ~src_off dst ~dst_off ~len =
    let a = Bigarray.Array1.sub src src_off len in
    let b = Bigarray.Array1.sub dst dst_off len in
    Bigarray.Array1.blit a b

  let rec t_fill k d =
    let blit d len =
      blit d.i ~src_off:d.i_pos d.t ~dst_off:d.t_len ~len ;
      { d with i_pos= d.i_pos + len
             ; t_len= d.t_len + len } in
    let rem = i_rem d in
    if rem < 0 then err_unexpected_end_of_input d
    else
      let need = d.t_need - d.t_len in
      if rem < need
      then let d = blit d rem in refill (t_fill k) d
      else let d = blit d need in k { d with t_need= 0 }

  let t_need n d = { d with t_need= n }

  let checksum d =
    let k d = match d.dd with
      | Dd { state; _ } ->
        let crc = unsafe_get_uint32_le d.t 0 in
        let isize = unsafe_get_uint32_le d.t 4 in

        if Optint.to_int32 d.crc = crc && Optint.to_int32 d.wr = isize
        then `End d
        else
          ( if Optint.to_int32 d.crc <> crc
            then err_invalid_checksum crc d
            else err_invalid_isize isize d )
      | _ -> assert false in
    t_fill k (t_need 8 d)

  let rec zero_terminated k d =
    let buf = Buffer.create 16 in

    let rec go d =
      if i_rem d >= 0
      then
        let i_pos = ref d.i_pos in
        let chr = ref '\000' in
        while d.i_len - !i_pos + 1 > 0
              && ( chr := unsafe_get_char d.i !i_pos
                 ; !chr != '\000' )
        do Buffer.add_char buf !chr ; incr i_pos done ;
        if i_rem d > 0 && !chr != '\000'
        then refill go { d with i_pos= !i_pos }
        else k (Some (Buffer.contents buf))
            { d with i_pos= !i_pos + 1 (* + '\000' *) }
      else err_unexpected_end_of_input d in
    go d

  let take_while n k d =
    let buf = Buffer.create 16 in

    let rec go n d =
      if i_rem d >= 0
      then
        let i_pos = ref d.i_pos in
        let r_pos = ref n in
        while d.i_len - !i_pos + 1 > 0 && !r_pos > 0
        do Buffer.add_char buf (unsafe_get_char d.i !i_pos)
         ; incr i_pos
         ; decr r_pos done ;
        if !r_pos == 0 then k (Buffer.contents buf) { d with i_pos= !i_pos }
        else refill (go !r_pos) { d with i_pos= !i_pos }
      else err_unexpected_end_of_input d in
    go n d

  let option_apply ~none x f = match x with
    | Some x -> f x
    | None -> none

  let zero = String.make 1 '\000'

  let option_iter f = function
    | Some x -> f x
    | None -> ()

  let string_of_hdr d =
    let hdr = Bytes.create 10 in
    bytes_unsafe_set_uint16_be hdr 0 0x1f8b ;
    bytes_unsafe_set_uint8 hdr 2 d.cm ;
    bytes_unsafe_set_uint8 hdr 3 d.flg ;
    bytes_unsafe_set_uint32_be hdr 4 d.mtime ;
    bytes_unsafe_set_uint8 hdr 8 d.xfl ;
    bytes_unsafe_set_uint8 hdr 9 d.os ;
    let res = Buffer.create 16 in
    Buffer.add_string res (Bytes.unsafe_to_string hdr) ;
    option_iter (fun fname -> Buffer.add_string res fname ; Buffer.add_char res '\000') d.fname ;
    option_iter (fun fcomment -> Buffer.add_string res fcomment ; Buffer.add_char res '\000') d.fcomment ;
    Buffer.contents res

  let rec fhcrc k d =
    let rec go d =
      if i_rem d >= 2
      then
        let _crc16 = unsafe_get_uint16_be d.i d.i_pos in
        let hdr = string_of_hdr d in
        let crc32 = Checkseum.Crc32.default in
        let crc32 = Checkseum.Crc32.digest_string hdr 0 (String.length hdr) crc32 in
        let _crc16 = Int32.(to_int (shift_right_logical (logand (Optint.to_int32 crc32) 0xFFFF0000l) 16)) in
        k { d with i_pos= d.i_pos + 2 }
      else if i_rem d = 0
      then refill go d
      else err_unexpected_end_of_input d in
    if d.flg land 0b10 != 0
    then go d else k d

  let fpayload k d =
    let ( >>= ) k f = k f in
    let noop v k = k v in
    let fiber : decoder -> signal =
      (if d.flg land 0b01000 != 0 then zero_terminated else noop None) >>= fun fname ->
      (if d.flg land 0b10000 != 0 then zero_terminated else noop None) >>= fun fcomment ->
      (fun d -> k { d with fname; fcomment; }) in
    fiber d

  let fextra k d =
    let rec go d =
      if i_rem d > 0
      then
        let len = unsafe_get_uint8 d.i d.i_pos in
        take_while len (fun v d -> k { d with fextra= Some v }) d
      else if i_rem d = 0
      then refill go d
      else err_unexpected_end_of_input d in
    go d

  let rec header d =
    let k d = match d.dd with
      | Hd { o; } ->
        let kfinal d =
          let window = De.make_window ~bits:15 in
          let state = De.Inf.decoder `Manual ~o ~w:window in
          let dd = Dd { state; window; o; } in
          De.Inf.src state d.i d.i_pos (i_rem d) ;
          decode { d with dd } in

        let id = unsafe_get_uint16_be d.i d.i_pos in
        if id != 0x1f8b
        then err_invalid_header d
        else
          let cm = unsafe_get_uint8 d.i (d.i_pos + 2) in
          let flg = unsafe_get_uint8 d.i (d.i_pos + 3) in
          let mtime = unsafe_get_uint32_be d.i (d.i_pos + 4) in
          let xfl = unsafe_get_uint8 d.i (d.i_pos + 8) in
          let os = unsafe_get_uint8 d.i (d.i_pos + 9) in

          if flg land 4 != 0
          then fextra (fpayload (fhcrc kfinal))
              { d with cm; flg; mtime; xfl; os; i_pos= d.i_pos + 10 }
          else fpayload (fhcrc kfinal)
              { d with cm; flg; mtime; xfl; os; i_pos= d.i_pos + 10 }
      | _ -> assert false in
    if i_rem d >= 10
    then k d
    else ( if i_rem d < 0
           then err_unexpected_end_of_input d
           else refill header d )

  and decode d = match d.dd with
    | Hd _ -> header d
    | Dd { state; o; _ } ->
      match De.Inf.decode state with
      | `Flush ->
        if d.f
        then flush decode d
        else
          let len = bigstring_length o - De.Inf.dst_rem state in
          let crc = Checkseum.Crc32.digest_bigstring o 0 len d.crc in
          flush decode { d with wr= Optint.add d.wr (Optint.of_int len)
                              ; crc
                              ; f= true }
      | `Await ->
        let len = i_rem d - De.Inf.src_rem state in
        refill decode { d with i_pos= d.i_pos + len }
      | `End ->
        if d.f
        then flush decode d (* Do nothing! *)
        else
          let len = bigstring_length o - De.Inf.dst_rem state in
          let crc = Checkseum.Crc32.digest_bigstring o 0 len d.crc in
          if len > 0
          then `Flush
              { d with i_pos= d.i_pos + (i_rem d - De.Inf.src_rem state)
                     ; wr= Optint.add d.wr (Optint.of_int len)
                     ; crc
                     ; f= true }
          else checksum { d with i_pos= d.i_pos + (i_rem d - De.Inf.src_rem state)
                               ; crc }
      | `Malformed err -> `Malformed err

  let src d s j l =
    if (j < 0 || l < 0 || j + l > bigstring_length s)
    then invalid_bounds j l ;
    let d =
      if (l == 0)
      then eoi d
      else
        { d with i= s
               ; i_pos= j
               ; i_len= j + l - 1 } in
    match d.dd with
    | Dd { state; _ } ->
      De.Inf.src state s j l ; d
    | Hd _ -> d

  let flush d = match d.dd with
    | Hd _ -> { d with f= false; }
    | Dd { state; _ } ->
      De.Inf.flush state ; { d with f= false; }

  let dst_rem d = match d.dd with
    | Hd _ -> invalid_arg "Invalid state to know bytes remaining"
    (* TODO(dinosaure): return [bigstring_length o]? *)
    | Dd { state; _ } -> De.Inf.dst_rem state

  let src_rem d = i_rem d

  let write { wr; _ } = Optint.to_int wr

  let decoder src ~o =
    let i, i_pos, i_len = match src with
      | `Manual -> bigstring_empty, 1, 0
      | `String x -> bigstring_of_string x, 0, String.length x - 1
      | `Channel _ -> bigstring_create io_buffer_size, 1, 0 in
    { i; i_pos; i_len
    ; src
    ; f= false
    ; wr= Optint.zero
    ; crc= Checkseum.Crc32.default
    ; dd= Hd { o; }
    ; flg= 0; cm= 0; mtime= 0l; xfl= 0; os= 0
    ; fextra= None
    ; fname= None
    ; fcomment= None
    ; t= bigstring_create 8
    ; t_need= 0
    ; t_len= 0
    ; k= decode }

  let reset d =
    let i, i_pos, i_len = match d.src with
      | `Manual -> bigstring_empty, 1, 0
      | `String x -> bigstring_of_string x, 0, String.length x - 1
      | `Channel _ -> bigstring_create io_buffer_size, 1, 0 in
    let o = match d.dd with
      | Hd { o; } -> o
      | Dd { o; _ } -> o in
    { i; i_pos; i_len
    ; f= false
    ; src= d.src
    ; wr= Optint.zero
    ; crc= Checkseum.Crc32.default
    ; dd= Hd { o; }
    ; flg= 0; cm= 0; mtime= 0l; xfl= 0; os= 0
    ; fextra= None
    ; fname= None
    ; fcomment= None
    ; t= bigstring_create 8
    ; t_need= 0
    ; t_len= 0
    ; k= decode }

  let filename { fname; _ } = fname
  let comment { fcomment; _ } = fcomment
end

module Def = struct
  type src = [ `Channel of in_channel | `String of string | `Manual ]
  type dst = [ `Channel of out_channel | `Buffer of Buffer.t | `Manual ]

  type encoder =
    { src : src
    ; dst : dst
    ; i : bigstring
    ; i_pos : int
    ; i_len : int
    ; o : bigstring
    ; o_pos : int
    ; o_len : int
    ; rd : optint
    ; crc : optint
    ; q : De.Queue.t
    ; s : De.Lz77.state
    ; e : De.Def.encoder
    ; w : De.window
    ; state : state
    ; flg : int
    ; xfl : int
    ; os : int
    ; mtime : int32
    ; fname : string option
    ; fcomment : string option
    ; k : encoder -> [ `Await of encoder | `Flush of encoder | `End of encoder ] }
  and state = Hd | Dd

  type ret = [ `Await of encoder | `End of encoder | `Flush of encoder ]

  let o_rem e = e.o_len - e.o_pos + 1
  let i_rem s = s.i_len - s.i_pos + 1

  let eoi e =
    De.Lz77.src e.s bigstring_empty 0 0 ;
    { e with i= bigstring_empty
           ; i_pos= 0
           ; i_len= min_int }

  let src e s j l =
    if (j < 0 || l < 0 || j + l > bigstring_length s)
    then invalid_bounds j l ;
    De.Lz77.src e.s s j l ;
    if (l == 0) then eoi e
    else
      let crc = Checkseum.Crc32.digest_bigstring s j l e.crc in
      let rd = Optint.add e.rd (Optint.of_int l) in
      { e with i= s; rd; crc; i_pos= j; i_len= j + l - 1 }

  let dst e s j l =
    if (j < 0 || l < 0 || j + l > bigstring_length s)
    then invalid_bounds j l ;
    ( ( match e.state with
          | Hd -> ()
          | Dd -> De.Def.dst e.e s j l )
    ; { e with o= s; o_pos= j; o_len= j + l - 1 } )

  let refill k e = match e.src with
    | `String _ -> k (eoi e)
    | `Channel ic ->
      let res = input_bigstring ic e.i 0 (bigstring_length e.i) in
      k (src e e.i 0 res)
    | `Manual -> `Await { e with k }

  let flush k e = match e.dst with
    | `Buffer b ->
      let len = bigstring_length e.o - o_rem e in
      for i = 0 to len - 1
      do Buffer.add_char b e.o.{i} done ;
      k (dst e e.o 0 (bigstring_length e.o))
    | `Channel oc ->
      output_bigstring oc e.o 0 (bigstring_length e.o - o_rem e) ;
      k (dst e e.o 0 (bigstring_length e.o))
    | `Manual -> `Flush { e with k }

  let identity e = `End e

  let rec checksum e =
    let k e =
      let checksum = Optint.to_int32 e.crc in
      let isize = Optint.to_int32 e.rd in
      unsafe_set_uint32_le e.o e.o_pos checksum ;
      unsafe_set_uint32_le e.o (e.o_pos + 4) isize ;
      flush identity { e with o_pos= e.o_pos + 8 } in
    if o_rem e >= 8 then k e else flush checksum e

  let make_block ?(last= false) e =
    if last = false
    then
      let literals = De.Lz77.literals e.s in
      let distances = De.Lz77.distances e.s in
      let dynamic = De.Def.dynamic_of_frequencies ~literals ~distances in
      { De.Def.kind= De.Def.Dynamic dynamic; last; }
    else { De.Def.kind= De.Def.Fixed; last; }

  let zero_terminated str kfinal e =
    let pos = ref 0 in
    Fmt.epr ">>> Do zero-terminated string.\n%!" ;
    let rec k e =
      let len = min (String.length str - !pos) (o_rem e) in
      for i = 0 to len - 1
      do unsafe_set_char e.o (e.o_pos + i) (String.get str (!pos + i)) done ;
      pos := !pos + len ;
      if !pos == String.length str
      then ( if o_rem { e with o_pos= e.o_pos + len } > 0
             then ( unsafe_set_uint8 e.o (e.o_pos + len) 0
                  ; kfinal { e with o_pos= e.o_pos + len + 1 } )
             else refill k { e with o_pos= e.o_pos + len } )
      else refill k { e with o_pos= e.o_pos + len } in
    k e

  let option_iter f = function
    | Some x -> f x
    | None -> ()

  let string_of_hdr e =
    let hdr = Bytes.create 10 in
    bytes_unsafe_set_uint16_be hdr 0 0x1f8b ;
    bytes_unsafe_set_uint8 hdr 2 8 ;
    bytes_unsafe_set_uint8 hdr 3 e.flg ;
    bytes_unsafe_set_uint32_be hdr 4 e.mtime ;
    bytes_unsafe_set_uint8 hdr 8 e.xfl ;
    bytes_unsafe_set_uint8 hdr 9 e.os ;
    let res = Buffer.create 16 in
    Buffer.add_string res (Bytes.unsafe_to_string hdr) ;
    option_iter (fun fname -> Buffer.add_string res fname ; Buffer.add_char res '\000') e.fname ;
    option_iter (fun fcomment -> Buffer.add_string res fcomment ; Buffer.add_char res '\000') e.fcomment ;
    Buffer.contents res

  let rec fhcrc e =
    let kfinal e =
      if i_rem e > 0 then De.Lz77.src e.s e.i e.i_pos (i_rem e) ;
      (* XXX(dinosaure): we need to protect [e.s] against EOI signal. *)
      De.Def.dst e.e e.o e.o_pos (o_rem e) ;
      encode { e with state= Dd } in
    let rec go e =
      if o_rem e >= 2
      then
        let crc32 = Checkseum.Crc32.default in
        let hdr = string_of_hdr e in
        let crc32 = Checkseum.Crc32.digest_string hdr 0 (String.length hdr) crc32 in
        let crc16 = Int32.(to_int (shift_right_logical (logand (Optint.to_int32 crc32) 0xFFFF0000l) 16)) in
        unsafe_set_uint16_be e.o e.o_pos crc16 ;
        kfinal { e with o_pos= e.o_pos + 2 }
      else flush go e in
    if e.flg land 0b10 != 0
    then go e else kfinal e

  and encode e = match e.state with
    | Hd ->
      let k e =
        unsafe_set_uint16_be e.o e.o_pos 0x1f8b ;
        unsafe_set_uint8 e.o (e.o_pos + 2) 8 ;
        unsafe_set_uint8 e.o (e.o_pos + 3) e.flg ;
        unsafe_set_uint32_be e.o (e.o_pos + 4) e.mtime ;
        unsafe_set_uint8 e.o (e.o_pos + 8) e.xfl ;
        unsafe_set_uint8 e.o (e.o_pos + 9) e.os ;

        let k = match e.fname, e.fcomment with
          | Some fname, Some fcomment -> zero_terminated fname (zero_terminated fcomment fhcrc)
          | Some fname, None -> zero_terminated fname fhcrc
          | None, Some fcomment -> zero_terminated fcomment fhcrc
          | None, None -> fhcrc in
        k { e with o_pos= e.o_pos + 10 } in
      if o_rem e >= 10 then k e else flush encode e
    | Dd ->
      let rec partial k e =
        k e (De.Def.encode e.e `Await)
      and compress e =
        match De.Lz77.compress e.s with
        | `Await ->
          Fmt.epr ">>> [compress] `Await.\n%!" ;
          refill compress { e with i_pos= e.i_pos + (i_rem e - De.Lz77.src_rem e.s) }
        | `Flush ->
          Fmt.epr ">>> [compress] `Flush.\n%!" ;
          encode_deflate e (De.Def.encode e.e `Flush)
        | `End ->
          Fmt.epr ">>> [compress] `End.\n%!" ;
          De.Queue.push_exn e.q De.Queue.eob ;
          let block = make_block ~last:true e in
          trailing e (De.Def.encode e.e (`Block block))
      and encode_deflate e = function
        | `Partial ->
          Fmt.epr ">>> [encode-deflate] `Partial.\n%!" ;
          let len = o_rem e - De.Def.dst_rem e.e in
          flush (partial encode_deflate) { e with o_pos= e.o_pos + len }
        | `Ok ->
          Fmt.epr ">>> [encode-deflate] `Ok.\n%!" ;
          compress e
        | `Block ->
          Fmt.epr ">>> [encode-deflate] `Block.\n%!" ;
          let block = make_block e in
          encode_deflate e (De.Def.encode e.e (`Block block))
      and trailing e = function
        | `Partial ->
          let len = o_rem e - De.Def.dst_rem e.e in
          Fmt.epr ">>> [trailing] `Partial.\n%!" ;
          Fmt.epr ">>> [trailing `Partial] DE wrote %d byte(s).\n%!" len ;
          Fmt.epr ">>> DE dst-rem: %d.\n%!" (De.Def.dst_rem e.e) ;
          Fmt.epr ">>> o-rem: %d.\n%!" (o_rem e) ;
          flush (partial trailing) { e with o_pos= e.o_pos + len }
        | `Ok ->
          Fmt.epr ">>> [trailing] `Ok.\n%!" ;
          let len = o_rem e - De.Def.dst_rem e.e in
          checksum { e with o_pos= e.o_pos + len }
        | `Block -> assert false in

      compress e

  let src_rem = i_rem
  let dst_rem = o_rem

  let is_some = function
    | Some _ -> true
    | None -> false

  let flg ~ascii ~hcrc ~extra ~filename ~comment =
    let flg = 0b0 lor (if ascii then 0b1 else 0b0) in
    let flg = flg lor (if hcrc then 0b10 else 0b0) in
    let flg = flg lor (if is_some extra then 0b100 else 0b0) in
    let flg = flg lor (if is_some filename then 0b1000 else 0b0) in
    let flg = flg lor (if is_some comment then 0b10000 else 0b0) in
    flg

  let os_to_int : int -> int = fun _ -> 0

  let encoder src dst ?(ascii= false) ?(hcrc= false) ?filename ?comment ~mtime os ~q ~w ~level =
    let i, i_pos, i_len = match src with
      | `Manual -> bigstring_empty, 1, 0
      | `String x -> bigstring_of_string x, 0, String.length x - 1
      | `Channel _ -> bigstring_create io_buffer_size, 1, 0 in
    let o, o_pos, o_len = match dst with
      | `Manual -> bigstring_empty, 1, 0
      | `Buffer _
      | `Channel _ -> bigstring_create io_buffer_size, 0, io_buffer_size - 1 in
    let rd, crc = match src with
      | `String x ->
        Optint.of_int (String.length x),
        Checkseum.Crc32.digest_string x 0 (String.length x) Checkseum.Crc32.default
      | `Manual | `Channel _ ->
        Optint.zero, Checkseum.Crc32.default in
    if level < 0 || level > 3
    then invalid_arg "Invalid compression level %d (must be in the range 0...3)" level ;
    let xfl = match level with
      | 0 | 1 -> 2
      | 2 | 3 -> 4
      | _ -> assert false in
    let flg = flg ~ascii ~hcrc ~extra:None ~filename ~comment in
    { src
    ; dst
    ; i; i_pos; i_len
    ; o; o_pos; o_len
    ; rd; crc
    ; e= De.Def.encoder `Manual ~q
    ; s= De.Lz77.state `Manual ~q ~w
    ; q
    ; w
    ; state= Hd
    ; xfl
    ; flg
    ; mtime
    ; os= os_to_int os
    ; fname= filename
    ; fcomment= comment
    ; k= encode }

  let encode e = e.k e
end
