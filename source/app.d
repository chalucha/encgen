import std.stdio;
import std.file;
import std.string;
import std.array;
import std.format;
import std.algorithm;
import std.range;
import std.path;
import std.conv;

enum char INDENTATION_CHAR = ' ';
enum int  INDENTATION_COUNT = 4;

struct Character
{
    ubyte s;
    dchar u;
}

struct CharRange
{
    Character[] mapping;
    uint min;
    uint max;
}

struct IndentWriter
{
    int indent;

    auto ref writeln(T...)(T args)
    {
        std.stdio.write(INDENTATION_CHAR.repeat(INDENTATION_COUNT * indent));
        std.stdio.writeln(args);
        return this;
    }

    auto ref writefln(T...)(T args)
    {
        std.stdio.write(INDENTATION_CHAR.repeat(INDENTATION_COUNT * indent));
        std.stdio.writefln(args);
        return this;
    }

    auto ref writef(T...)(T args)
    {
        std.stdio.write(INDENTATION_CHAR.repeat(INDENTATION_COUNT * indent));
        std.stdio.writef(args);
        return this;
    }

    auto ref write(T...)(T args)
    {
        std.stdio.write(INDENTATION_CHAR.repeat(INDENTATION_COUNT * indent));
        std.stdio.write(args);
        return this;
    }

    alias indent this;
}

void writeCharRangesInfo(Character[] chars)
{
    writeln("Ranges with different char and unicode values:");

    chars.sort!((a,b) => a.u < b.u);
    
    CharRange[] ranges;
    CharRange cur;
    foreach(ch; chars.filter!(a=>a.u != '\uFFFD'))
    {
        //writefln("%04x - %02x", ch.u, ch.s);
        if(cur.max + 1 == ch.u)
        {
            cur.max = ch.u;
            if(ch.u != cast(dchar)ch.s) cur.mapping ~= ch;
        }
        else if(cur != CharRange.init)
        {
            ranges ~= cur;
            cur = CharRange.init;
            cur.min = cur.max = ch.u;
            if(ch.u != cast(dchar)ch.s) cur.mapping ~= ch;
        }
    }
    ranges ~= cur;
    
    foreach(r; ranges)
    {
        writefln("%04x:%04x - %s", r.min, r.max, r.mapping);
        assert(r.mapping.length == 0 || (r.max - r.min + 1) == r.mapping.length);
    }

    writeln();
    writeln();
}

void writeCharMapC2U(ref IndentWriter wr, ref Character[] chars)
{
    chars.sort!((a,b) => a.s < b.s);

    writeln();
    wr.writeln("immutable wstring charMap =")++;
    wr.write("\"");
    foreach(int i, ch; chars)
    {
        writef("\\u%04X", ch.u);
        if(i != 0 && (i + 1) % 8 == 0)
        {
            if(i + 1 != chars.length)
            {
                write("\"~\n");
                wr.write("\"");
            }
            else
            {
                writeln("\";");
            }
        }
        else if(i + 1 == chars.length)
        {
            writeln("\";");
        }
    }
    wr--;
}

void writeCharMapU2C(ref IndentWriter wr, ref Character[] chars)
{
    auto valid = chars.filter!(a => a.u != '\uFFFD').array;
    auto bst = valid.sort!((a,b) => a.u < b.u).toBST;
    
    assert(bst.isValidBST!((a,b) => a.u < b.u));
    assert(bst.length == valid.length);

    writeln();
    wr.writeln("immutable Tuple!(wchar, char)[] bstMap = [")++;
    wr.write();

    foreach(i, ch; bst)
    {
        writef("tuple('\\u%04X','\\x%02X')", ch.u, ch.s);
        if ((i+1) % 3 == 0)
        {
            if (i + 1 < bst.length)
            {
                writeln(",");
                wr.write();
            }
        }
        else if (i + 1 == bst.length) writeln();
        else if (i + 1 < bst.length) write(", ");
    }
    wr--;
    wr.writeln("];");
}

void main(string[] args)
{
    if(args.length < 2) assert(0, "Encoding specification file needed!");

    auto text = cast(string)read(args[1]);

    bool hasUndefined = false;

    // characters
    auto chars = Appender!(Character[])();
    foreach(line; text.lineSplitter)
    {
        ubyte s;
        uint u;

        if(line.length == 0 || line[0] == '#')
            continue;

        //debug writeln(line);
        s = to!ubyte(line[2..4], 16);

        if(line[6] == 'x')
            u = to!uint(line[7..11], 16);
        else
        {
            u = '\uFFFD';
            hasUndefined = true;
        }

        //writefln("0x%02X -> 0x%04X", s, u);
        chars.put(Character(s, u));
    }

    auto res = chars.data.find!(a => cast(uint)a.s != a.u).array; // sorted by char value
    auto startsWith = res[0].s;

    // debug writeCharRangesInfo(chars.data);

    IndentWriter wr;

    auto encName = args[1].stripExtension().baseName;
    auto encTypeName = encName.filter!(a=>a != '-' && a != '_').to!string.capitalize;
    wr.writeln("//=============================================================================");
    wr.writefln("//          %s", encName);
    wr.writeln("//=============================================================================");
    writeln();
    wr.writefln("/// Defines a %s-encoded character.", encName);
    wr.writefln("enum %sChar : ubyte { init }", encTypeName);
    writeln();
    wr.writeln("/**");
    wr.writefln(" * Defines an %s-encoded string (as an array of $(D", encTypeName);
    wr.writefln(" * immutable(%sChar))).", encTypeName);
    wr.writeln(" */");
    wr.writefln("alias %sString = immutable(%sChar)[];", encTypeName, encTypeName);
    writeln();
    wr.writefln("template EncoderInstance(CharType : %sChar)", encTypeName);
    wr.writeln("{")++;

    wr.writeln("import std.typecons : Tuple, tuple;");
    writeln();
    wr.writefln("alias E = %sChar;", encTypeName);
    wr.writefln("alias EString = %sString;", encTypeName);
    writeln();

    wr.writeln("@property string encodingName()");
    wr.writeln("{")++;
    wr.writefln("return \"%s\";", encName.toLower)--;
    wr.writeln("}");

    //char map c2u
    writeCharMapC2U(wr, res);

    //char map u2c
    writeCharMapU2C(wr, res);

    //canEncode
    writeln();
    wr.writeln("bool canEncode(dchar c)");
    wr.writeln("{")++;
    wr.writefln("if (c < %#02X) return true;", startsWith);
    wr.writeln("if (c >= 0xFFFD) return false;");
    writeln();
    wr.writeln("auto idx = 0;");
    wr.writeln("while (idx < bstMap.length)");
    wr.writeln("{")++;
    wr.writeln("if (bstMap[idx][0] == c) return true;");
    wr.writeln("idx = bstMap[idx][0] > c ? 2 * idx + 1 : 2 * idx + 2; // next BST index")--;
    wr.writeln("}");
    writeln();
    wr.writeln("return false;")--;
    wr.writeln("}");

    //isValidCodeUnit
    writeln();
    wr.writefln("bool isValidCodeUnit(%sChar c)", encTypeName);
    wr.writeln("{")++;
    if (hasUndefined)
    {
        wr.writefln("if (c < %#02X) return true", startsWith);
        wr.writefln("return charMap[c-%#02X] != 0xFFFD;", startsWith)--;
    }
    else
        wr.writeln("return true;")--;
    wr.writeln("}");

    //encodedLength
    writeln();
    wr.writeln("size_t encodedLength(dchar c)");
    wr.writeln("in");
    wr.writeln("{")++;
    wr.writeln("assert(canEncode(c));")--;
    wr.writeln("}");
    wr.writeln("body");
    wr.writeln("{")++;
    wr.writeln("return 1;")--;
    wr.writeln("}");

    //encodeViaWrite
    writeln();
    wr.writeln("void encodeViaWrite()(dchar c)");
    wr.writeln("{")++;
    wr.writefln("if (c < %#02X) {}", startsWith); //return the same
    wr.writeln("else if (c >= 0xFFFD) { c = '?'; }"); //cant encode
    wr.writeln("else");
    wr.writeln("{")++;
    wr.writeln("auto idx = 0;");
    wr.writeln("while (idx < bstMap.length)");
    wr.writeln("{")++;
    wr.writeln("if (bstMap[idx][0] == c)");
    wr.writeln("{")++;
    wr.writefln("write(cast(%sChar)bstMap[idx][1]);", encTypeName);
    wr.writeln("return;")--;
    wr.writeln("}");
    wr.writeln("idx = bstMap[idx][0] > c ? 2 * idx + 1 : 2 * idx + 2; // next BST index")--;
    wr.writeln("}");
    wr.writeln("c = '?';")--;
    wr.writeln("}");
    wr.writefln("write(cast(%sChar)c);", encTypeName)--;
    wr.writefln("}");

    //skipViaRead
    writeln();
    wr.writeln("void skipViaRead()()");
    wr.writeln("{")++;
    wr.writeln("read();")--;
    wr.writeln("}");

    //decodeViaRead
    writeln();
    wr.writeln("dchar decodeViaRead()()");
    wr.writeln("{")++;
    wr.writefln("%sChar c = read();", encTypeName);
    wr.writefln("return (c >= %#02X) ? charMap[c-%#02X] : c;", startsWith, startsWith)--;
    wr.writeln("}");

    //safeDecodeViaRead
    writeln();
    wr.writeln("dchar safeDecodeViaRead()()");
    wr.writeln("{")++;
    wr.writefln("%sChar c = read();", encTypeName);
    if (hasUndefined)
    {
        wr.writefln("dchar d = (c >= %#02X) ? charMap[c-%#02X] : c;", startsWith, startsWith);
        wr.writeln("return d == 0xFFFD ? INVALID_SEQUENCE : d;")--;
    }
    else
        wr.writefln("return (c >= %#02X) ? charMap[c-%#02X] : c;", startsWith, startsWith)--;
    wr.writeln("}");

    //decodeReverseViaRead
    writeln();
    wr.writeln("dchar decodeReverseViaRead()()");
    wr.writeln("{")++;
    wr.writefln("%sChar c = read();", encTypeName);
    wr.writefln("return (c >= %#02X) ? charMap[c-%#02X] : c;", startsWith, startsWith)--;
    wr.writeln("}");

    //replacementSequence
    writeln();
    wr.writeln("@property EString replacementSequence()");
    wr.writeln("{")++;
    wr.writeln(`return cast(EString)("?");`)--;
    wr.writeln("}");

    writeln();
    wr.writeln("mixin EncoderFunctions;")--;
    wr.writeln("}");
}

auto toBST(R)(R input) 
    if (isRandomAccessRange!R)
{
    auto getMid(size_t start, size_t end)
    {
        import std.math;
        auto n = end - start + 1; //počet prvků
        auto h = cast(size_t)ceil(log2(n + 1)); //výška stromu
        auto p = pow(2, h - 1);

        auto m = n/2;
        if(m == p - 1) return start + m;
        return start + min(p - 1, n - p/2);
    }

    void fillBST(ref ElementType!R[] res, size_t start, size_t end, size_t idx)
    {
        if(start > end || end == size_t.max) return;

        auto mid = getMid(start, end);

        //writefln("S: %s, E: %s, IDX: %s, MID: %s", start, end, idx, mid);
        auto i = input[mid];
        res[idx] = i;

        //writefln("VAL: %s", input[mid]);

        fillBST(res, start, mid - 1, 2 * idx + 1);
        fillBST(res, mid + 1, end, 2 * idx + 2);
    }

    ElementType!R[] res;
    res.length = input.length;

    fillBST(res, 0, input.length - 1, 0);
    return res;
}

bool isValidBST(alias pred = "a<b", R)(R input) 
    if (isRandomAccessRange!R)
{
    import std.functional;

    foreach(i; 0..input.length)
    {
        auto left = 2*i+1;
        auto right = 2*i+2;
        if(left < input.length && !binaryFun!pred(input[left], input[i])) return false;
        if(right < input.length && !binaryFun!pred(input[i], input[right])) return false;
    }
    return true;
}

unittest
{
    auto a = [1];
    auto b = a.toBST;
    writefln("%s\n%s\n", a, b);
    assert(b == [1]);
    assert(b.isValidBST);

    a = [1, 2];
    b = a.toBST;
    writefln("%s\n%s\n", a, b);
    assert(b == [2, 1]);
    assert(b.isValidBST);

    a = [1, 2, 3];
    b = a.toBST;
    writefln("%s\n%s\n", a, b);
    assert(b == [2, 1, 3]);
    assert(b.isValidBST);

    a = [1, 2, 3, 4];
    b = a.toBST;
    writefln("%s\n%s\n", a, b);
    assert(b == [3, 2, 4, 1]);
    assert(b.isValidBST);

    a = [1, 2, 3, 4, 5];
    b = a.toBST;
    writefln("%s\n%s\n", a, b);
    assert(b == [4, 2, 5, 1, 3]);
    assert(b.isValidBST);

    a = [1, 2, 3, 4, 5, 6];
    b = a.toBST;
    writefln("%s\n%s\n", a, b);
    assert(b == [4, 2, 6, 1, 3, 5]);
    assert(b.isValidBST);

    a = [1, 2, 3, 4, 5, 6, 7];
    b = a.toBST;
    writefln("%s\n%s\n", a, b);
    assert(b == [4, 2, 6, 1, 3, 5, 7]);
    assert(b.isValidBST);
}
