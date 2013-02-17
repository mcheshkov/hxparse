package hxparse;

import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.Tools;
using Lambda;

typedef ParserCase = {
	expr: Expr,
	head: Expr,
	tail: Array<Expr>
}

enum CaseGroup {
	Simple(group:Array<ParserCase>);
	Complex(c:ParserCase);
}

class ParserBuilder {
	static public function build():Array<haxe.macro.Field> {
		var fields = Context.getBuildFields();
		for (field in fields) {
			switch(field.kind) {
				case FFun(fun) if (fun.expr != null):
					fun.expr = map(true, fun.expr);
				case _:
			}
		}
		return fields;
	}
	
	static function punion(p1:Position, p2:Position) {
		var p1 = Context.getPosInfos(p1);
		var p2 = Context.getPosInfos(p2);
		return Context.makePosition({
			file: p1.file,
			min: p1.min < p2.min ? p1.min : p2.min,
			max: p1.max > p2.max ? p1.max : p2.max
		});
	}
	
	static function map(needVal:Bool, e:Expr) {
		return switch(e.expr) {
			case ESwitch({expr: EConst(CIdent("stream"))}, cl, edef):
				if (edef != null)
					cl.push({values: [macro _], expr: edef, guard: null});
				transformCases(needVal, cl);
			case EBlock([]):
				e;
			case EBlock(el):
				var elast = el.pop();
				var el = el.map(map.bind(false));
				el.push(map(true, elast));
				macro $b{el};
			case _: e.map(map.bind(true));
		}
	}
	
	static var fcount = 0;
	
	static function transformCases(needVal:Bool, cl:Array<Case>) {
		var groups = [];
		var group = [];
		var def = macro null;
		for (c in cl) {
			switch(c.values) {
				case [{expr:EArrayDecl(el)}]:
					var head = el.shift();
					var chead = {head:head, tail: el, expr:map(true,c.expr)};
					switch(head.expr) {
						case EBinop(_):
							if (group.length > 0) groups.push(Simple(group));
							groups.push(Complex(chead));
							group = [];
						case _:
							group.push(chead);
					}
				case [{expr:EConst(CIdent("_"))}]:
					def = map(true, c.expr);
				case [e]:
					Context.error("Expected [ patterns ]", e.pos);
				case _:
					Context.error("Comma notation is not allowed while matching streams", punion(c.values[0].pos, c.values[c.values.length - 1].pos));
			}
		}
		if (group.length > 0)
			groups.push(Simple(group));
			
		var last = groups.pop();
		var elast = makeCase(last,def);
		while (groups.length > 0) {
			elast = makeCase(groups.pop(), elast);
		}
		return elast;
	}
	
	static var unexpected = macro throw new hxparse.Parser.Unexpected(peek());
		
	static function makeCase(g:CaseGroup, def:Expr) {
		return switch(g) {
			case Simple(group):
				var cl = group.map(makeInner);
				cl.iter(function(c) {
					c.expr = macro { junk(); ${c.expr}; };
				});
				{
					pos: def.pos,
					expr: ESwitch(macro peek(), cl, def)
				}
			case Complex(c):
				var inner = makeInner(c);
				makePattern(c.head, inner.expr, def);
		}
	}
	
	static function makeInner(c:ParserCase) {
		var last = c.tail.pop();
		if (last == null) {
			return {values:[c.head], guard:null, expr: c.expr};
		}
		var elast = makePattern(last, c.expr, unexpected);
		while (c.tail.length > 0)
			elast = makePattern(c.tail.pop(), elast, unexpected);
		return {values: [c.head], guard: null, expr: elast};
	}
	
	static function makePattern(pat:Expr, e:Expr, def:Expr) {
		return switch(pat.expr) {
			case EBinop(OpAssign, {expr: EConst(CIdent(s))}, e2):
				macro @:pos(pat.pos) {
					var $s = $e2;
					if ($i{s} != null) {
						$e;
					} else
						$def;
				}
			case EBinop(OpBoolAnd, e1, e2):
				macro @:pos(pat.pos) switch peek() {
					case $e1 if ($e2):
						junk();
						$e;
					case _: $def;
				}
			case _:
				macro @:pos(pat.pos) switch peek() {
					case $pat:
						junk();
						$e;
					case _: $def;
				}
		}
	}
}