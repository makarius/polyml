(*
    Title:      Standard Basis Library: Array2 structure and signature.
    Author:     David Matthews
    Copyright   David Matthews 2000, 2005

	This library is free software; you can redistribute it and/or
	modify it under the terms of the GNU Lesser General Public
	License as published by the Free Software Foundation; either
	version 2.1 of the License, or (at your option) any later version.
	
	This library is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	Lesser General Public License for more details.
	
	You should have received a copy of the GNU Lesser General Public
	License along with this library; if not, write to the Free Software
	Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*)

(* G&R 2004 status: modified to accommodate changes in Array structure. *)


signature ARRAY2 =
sig
	eqtype 'a array
	type 'a region =
	{
		base : 'a array,
		row : int,
		col : int,
		nrows : int option,
		ncols : int option
	}
	datatype traversal = RowMajor | ColMajor
	val array: int * int * 'a -> 'a array
	val fromList: 'a list list -> 'a array
	val tabulate: traversal -> int * int * (int * int -> 'a) -> 'a array
	val sub: 'a array * int * int -> 'a
	val update: 'a array * int * int * 'a -> unit
	val dimensions: 'a array -> int * int
	val nCols: 'a array -> int
	val nRows: 'a array -> int
	val row: 'a array * int -> 'a Vector.vector
	val column: 'a array * int -> 'a Vector.vector
	val copy:
	 {src : 'a region, dst : 'a array, dst_row : int, dst_col : int} -> unit
	val appi: traversal -> (int * int * 'a -> unit) -> 'a region -> unit
	val app: traversal -> ('a -> unit) -> 'a array -> unit
	val modifyi: traversal -> (int * int * 'a -> 'a) -> 'a region -> unit
	val modify: traversal -> ('a -> 'a) -> 'a array -> unit
	val foldi:
		traversal -> (int * int * 'a * 'b -> 'b) -> 'b -> 'a region -> 'b
	val fold: traversal -> ('a * 'b -> 'b) -> 'b -> 'a array -> 'b
end;


structure Array2 : ARRAY2 =
struct
	(* There are lots of possible implementations with advantages and
	   disadvantages according to the requirements.  I'm choosing a very
	   simple implementation in terms of arrays of arrays. *)
	(* This is implemented as a vector of rows i.e. Vector.sub(v, 0)
	   returns the first row, Vector.sub(v, 1) the second. *)
	(* N.B. we have to use a datatype here so that we can install a
	   pretty printer. *)
	datatype 'a array = Array2 of 'a Array.array Vector.vector

	type 'a region =
	{
		base : 'a array,
		row : int,
		col : int,
		nrows : int option,
		ncols : int option
	}

	datatype traversal = RowMajor | ColMajor

	fun array(r, c, init) =
		Array2(Vector.tabulate(r, fn _ => Array.array(c, init)))

	fun fromList l =
	let
		(* Check that all the lists have the same length. *)
		fun checkLen(l, NONE) = SOME(List.length l)
		  | checkLen(l, SOME i) =
		  		if List.length l <> i
				then raise Size
				else SOME i
		val checkLengths = List.foldl checkLen NONE l
	in
		(* Build the arrays. *)
		Array2(Vector.fromList(List.map (fn ll => Array.fromList ll) l))
	end

	fun tabulate RowMajor (r, c, f) =
		Array2(Vector.tabulate(r, fn r' => Array.tabulate(c, fn c' => f(r', c'))))
	|   tabulate ColMajor (r, c, f) =
		let
			(* First tabulate into column-major vectors. *)
			val vecs =
				Vector.tabulate(c,
					fn c' => Vector.tabulate(r, fn r' => f(r', c')))
		in
			(* Convert this to row-major arrays. *)
			tabulate RowMajor (r, c,
				fn (r', c') => Vector.sub(Vector.sub(vecs, c'), r'))
		end

	(* Internal functions: These are used where we have already checked
	   that the indexes are in range.  Actually, at the moment these
	   repeat the checking anyway. *)
	fun uncheckedSub(Array2 a, i, j) = Array.sub(Vector.sub(a, i), j)
	and uncheckedUpdate(Array2 arr, i, j, a) = Array.update(Vector.sub(arr, i), j, a)

	fun sub(Array2 a, i, j) = Array.sub(Vector.sub(a, i), j)

    fun update (Array2 arr, i, j, a) = Array.update(Vector.sub(arr, i), j, a)

	fun nRows(Array2 a) = Vector.length a

	(* This next is wrong in the case where nRows = 0. It'll do
	   for the moment. *)
	fun nCols(Array2 a) = Array.length(Vector.sub(a, 0))

	fun dimensions a = (nRows a, nCols a)

	fun row(Array2 a, i) = Array.vector(Vector.sub(a, i))

	fun column(a, j) = Vector.tabulate(nRows a, fn i => sub(a, i, j))

	(* Internal function.  Check that the region is valid and get
	   the actual lengths. *)
	fun getRegion {base, row, col, nrows, ncols} =
	let
		val (lRows, lCols) = dimensions base
		val nrows' =
			case nrows of
				NONE =>
					if row < 0 orelse row > lRows
					then raise Subscript
					else lRows - row
			|   SOME r =>
					if r < 0 orelse row < 0 orelse r+row > lRows
					then raise Subscript
					else r
		val ncols' =
			case ncols of
				NONE =>
					if col < 0 orelse col > lCols
					then raise Subscript
					else lCols - col
			|   SOME c =>
					if c < 0 orelse col < 0 orelse c+col > lCols
					then raise Subscript
					else c
	in
		(nrows', ncols')
	end

	fun copy {src as {base, row, col, ...}, dst, dst_row, dst_col} =
	let
		(* Check the region and get the lengths. *)
		val (nrows, ncols) = getRegion src
		val (dRows, dCols) = dimensions dst

		fun copyIncrementing(r, c) =
			if r = nrows then ()
			else if c = ncols then copyIncrementing(r+1, 0)
			else
			   (
			   	uncheckedUpdate(dst, dst_row+r, dst_col+c,
					uncheckedSub(base, row+r, col+c));
				copyIncrementing(r, c+1)
			   )

		fun copyDecrementing(r, c) =
			if r < 0 then ()
			else if c < 0 then copyDecrementing(r-1, ncols-1)
			else
			   (
			   	uncheckedUpdate(dst, dst_row+r, dst_col+c,
					uncheckedSub(base, row+r, col+c));
				copyDecrementing(r, c-1)
			   )
	in
		(* Check the destination *)
		if dst_row < 0 orelse dst_col < 0 orelse
		   dst_row+nrows > dRows orelse dst_col+ncols > dCols
		then raise Subscript
		else (* We have to be careful if dst = src and the regions
				overlap.  Rather than treat the overlapped case
				specially we simply choose incrementing or decrementing
				copies depending on the indexes. *)
			if dst_row < row orelse (dst_row = row andalso dst_col < col)
		then copyIncrementing(0, 0)
		else copyDecrementing(nrows-1, ncols-1)
	end

	fun appi tr f (reg as {base, row, col, ...}) =
	let
		val (nrows, ncols) = getRegion reg
		fun appRowMajor (r, c) =
			if r = nrows then ()
			else if c = ncols then appRowMajor(r+1, 0)
			else
			  (
			   f(r+row, c+col, uncheckedSub(base, r+row, c+col));
			   appRowMajor(r, c+1)
			  )
		fun appColMajor (r, c) =
			if c = ncols then ()
			else if r = nrows then appColMajor(0, c+1)
			else
			  (
			   f(r+row, c+col, uncheckedSub(base, r+row, c+col));
			   appColMajor(r+1, c)
			  )
	in
		case tr of
			RowMajor => appRowMajor(0, 0)
		|   ColMajor => appColMajor(0, 0)
	end

	fun app tr f arr =
		appi tr (f o #3) {base=arr, row=0, col=0, nrows=NONE, ncols=NONE}

	(* Just define modify in terms of app. *)
	fun modifyi tr f (reg as {base, ...}) =
		appi tr (fn(i, j, a) => uncheckedUpdate(base, i, j, f(i, j, a))) reg
	fun modify tr f arr =
		modifyi tr (f o #3) {base=arr, row=0, col=0, nrows=NONE, ncols=NONE}

	(* Fold is fairly similar to app. *)
	fun foldi tr f init (reg as {base, row, col, ...}) =
	let
		val (nrows, ncols) = getRegion reg
		fun foldRowMajor (r, c, i) =
			if r = nrows then i
			else if c = ncols then foldRowMajor(r+1, 0, i)
			else
			   foldRowMajor(r, c+1,
					f(r+row, c+col, uncheckedSub(base, r+row, c+col), i))

		fun foldColMajor (r, c, i) =
			if c = ncols then i
			else if r = nrows then foldColMajor(0, c+1, i)
			else
			   foldColMajor(r+1, c,
					f(r+row, c+col, uncheckedSub(base, r+row, c+col), i))
	in
		case tr of
			RowMajor => foldRowMajor(0, 0, init)
		|   ColMajor => foldColMajor(0, 0, init)
	end

	fun fold tr f init arr = 
		foldi tr (fn (_,_,a,b) => f (a,b)) init 
                {base=arr, row=0, col=0, nrows=NONE, ncols=NONE}

	local
		(* Install the pretty printer for arrays *)
		(* We may have to do this outside the structure if we
		   have opaque signature matching. *)
		fun 'a pretty(put: string->unit, beg: int*bool->unit,
				   brk: int*int->unit, nd: unit->unit)
				  (depth: int)
				  (printElem: 'a * int -> unit)
				  (x: 'a array): unit =
			let
				val (nrows, ncols) = dimensions x

				fun put_elem (r: int, c: int, w: 'a, d: int) =
					if d = 0 then (put "..."; d-1)
					else if d < 0 then d-1
					else
					(
					printElem(w, d-1);
					if c <> ncols-1 then (put ","; brk(1, 0)) else ();
					d-1
					)

				fun putRow(r, d) =
					if r = nrows orelse d < 0 then ()
					else if d = 0 then put "..."
					else
						(
						beg(3, false);
						put "["; brk(1, 2);
						(* Print this single row. *)
						foldi RowMajor put_elem depth
							{base=x, row=r, col=0, nrows=SOME 1, ncols=NONE};
						put "]";
						nd();
						if r = nrows-1 then ()
						else (put ","; brk(1, 0); putRow(r+1, d-1))
						)
			in
				beg(3, true);
				put "fromList[";
				if depth <= 0 then put "..."
				else putRow(0, depth);
				put "]";
				nd()
			end
	in
		val () = PolyML.install_pp pretty
	end
end;


(* Install overloaded equality functions.  This has two effects.
   It speeds up equality checking by providing a type-specific
   equality function which is faster than the default structure
   equality.  More importantly, it indicates to the type checker
   that equality on this type is allowed whatever the 'a .  That
   does not comply with the Definition of Standard ML, which
   restricts this privilege to ref, but is implied by the Basis
   library definition. *)
local
    val f : word*word->bool =
		RunCall.run_call2 RuntimeCalls.POLY_SYS_word_eq
in
   fun it (x: 'a Array2.array, y: 'a Array2.array) =
   		RunCall.unsafeCast f (x,y)
end;
RunCall.addOverload it "=";
local
    val f : word*word->bool =
		RunCall.run_call2 RuntimeCalls.POLY_SYS_word_neq
in
   fun it (x: 'a Array2.array, y: 'a Array2.array) =
   		RunCall.unsafeCast f (x,y)
end;
RunCall.addOverload it "<>";

