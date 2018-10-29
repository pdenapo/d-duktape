/**
    Duktape exemples.
*/
import duktape;
import std.stdio;


enum Direction { up, down, left, right }

static void print(string msg)
{
    writeln(msg);
}

class Person
{
private:
    Direction[] _moveHistory;

public:
    this() { }


    void move(Direction dir)
    {
        _moveHistory ~= dir;
    }

    @property Direction[] moveHistory()
    {
        return _moveHistory;
    }
}

int main()
{
    auto ctx = new DukContext();

    ctx.registerGlobal!print;

    ctx.createNamespace("Game")
        .register!Direction
        .register!Person
        .finalize();

    ctx.evalString(q"{
        p = new Game.Person();

        p.move(Game.Direction.up);
        p.move(Game.Direction.down);
        p.move(Game.Direction.left);
        p.move(Game.Direction.right);

        print(p.moveHistory.toString());
    }");

    return 0;
}
