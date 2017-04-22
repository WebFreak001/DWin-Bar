module dwinbar.widget;

import dwinbar.bar;
import dwinbar.backend.xbackend;

import derelict.freetype.ft;

import std.traits;

public import imageformats;

ubyte[n] mix(ubyte n, F)(ubyte[n] a, ubyte[n] b, F fac)
		if (n >= 1 && n <= 4 && isFloatingPoint!F)
{
	ubyte[n] mixed;
	foreach (i; 0 .. n)
		mixed[i] = cast(ubyte)(a[i] * (1 - fac) + b[i] * fac);
	return mixed;
}

ubyte[4] blend(ubyte[] fg, ubyte[] bg, ubyte opacity = 255)
{
	ubyte[4] r;
	if (opacity != 255)
	{
		ubyte modA = cast(ubyte)(fg[3] * cast(int) opacity / 256);
		r[3] = cast(ubyte)(modA + bg[3] * (255 - modA) / 256);
		if (r[3] == 0)
			return r;
		foreach (c; 0 .. 3)
			r[c] = (fg[c] * cast(int) opacity / 256 + bg[c] * (255 - modA) / 256) & 0xFF;
	}
	else
	{
		r[3] = cast(ubyte)(fg[3] + bg[3] * (255 - fg[3]) / 256);
		if (r[3] == 0)
			return r;
		foreach (c; 0 .. 3)
			r[c] = (fg[c] + bg[c] * (255 - fg[3]) / 256) & 0xFF;
	}
	return r;
}

void fillRect(ubyte n)(ref IFImage image, int x, int y, int w, int h, ubyte[n] pixel)
		if (n >= 1 && n <= 4)
{
	assert(n == image.c, "Wrong image format");
	if (w <= 0 || h <= 0)
		return;
	if (x + w < 0 || y + h < 0 || x >= image.w || y >= image.h)
		return;
	if (x < 0)
	{
		w -= x;
		x = 0;
	}
	if (y < 0)
	{
		h -= y;
		y = 0;
	}
	if (w <= 0 || h <= 0)
		return;
	if (x + w > image.w)
		w = image.w - x;
	if (y + h > image.h)
		h = image.h - y;
	ubyte[] row = new ubyte[n * w];
	for (int xx = 0; xx < w; xx++)
		row[xx * n .. xx * n + n] = pixel;
	for (int v; v < h; v++)
		image.pixels[(x + (y + v) * image.w) * n .. (x + w + (y + v) * image.w) * n] = row;
}

IFImage premultiply(IFImage image)
{
	if (image.c != ColFmt.RGBA)
		return image;
	for (int y = 0; y < image.h; y++)
		for (int x = 0; x < image.w; x++)
		{
			ubyte a = image.pixels[(x + y * image.w) * 4 + 3];
			image.pixels[(x + y * image.w) * 4 + 0] = cast(ubyte)(
					image.pixels[(x + y * image.w) * 4 + 0] * a / 256);
			image.pixels[(x + y * image.w) * 4 + 1] = cast(ubyte)(
					image.pixels[(x + y * image.w) * 4 + 1] * a / 256);
			image.pixels[(x + y * image.w) * 4 + 2] = cast(ubyte)(
					image.pixels[(x + y * image.w) * 4 + 2] * a / 256);
		}
	return image;
}

void draw(ref IFImage image, FT_Bitmap bitmap, int x, int y, ubyte[4] color)
{
	assert(image.c == ColFmt.RGBA, "Wrong image format");
	assert(bitmap.pitch > 0);
	int w = bitmap.width;
	int h = bitmap.rows;
	if (x + w < 0 || y + h < 0 || x >= image.w || y >= image.h)
		return;
	if (x < 0)
	{
		w -= x;
		x = 0;
	}
	if (w <= 0 || h <= 0)
		return;
	if (x + w >= image.w)
		w = image.w - x - 1;
	if (bitmap.pixel_mode == FT_PIXEL_MODE_GRAY)
		for (int ly; ly < h; ly++)
			for (int lx; lx < w; lx++)
			{
				if (ly + y < 0 || ly + y >= image.h)
					continue;
				ubyte[4] col = color;
				ubyte a = bitmap.buffer[lx + ly * bitmap.pitch];
				col = mix(image.pixels[(lx + x + (ly + y) * image.w) * 4 .. (lx + x + (ly + y) * image.w)
						* 4 + 4][0 .. 4], color, a / 255.0f);
				image.pixels[(lx + x + (ly + y) * image.w) * 4 .. (lx + x + (ly + y) * image.w) * 4 + 4] = col;
			}
	else
		throw new Exception("Unsupported bitmap format");
}

void draw(ref IFImage image, IFImage bitmap, int x, int y, int width = 0,
		int height = 0, ubyte opacity = 255)
{
	assert(bitmap.c == image.c && image.c == ColFmt.RGBA, "Wrong image format");
	int w = width == 0 ? bitmap.w : width;
	int h = height == 0 ? bitmap.h : height;
	if (w > bitmap.w)
		w = bitmap.w;
	if (h > bitmap.h)
		h = bitmap.h;
	if (x + w < 0 || y + h < 0 || x >= image.w || y >= image.h || opacity == 0)
		return;
	if (x < 0)
	{
		w -= x;
		x = 0;
	}
	if (w <= 0 || h <= 0)
		return;
	if (x + w >= image.w)
		w = image.w - x - 1;
	for (int ly; ly < h; ly++)
		for (int lx; lx < w; lx++)
		{
			if (ly + y < 0 || ly + y >= image.h)
				continue;
			image.pixels[(lx + x + (ly + y) * image.w) * 4 .. (lx + x + (ly + y) * image.w) * 4 + 4] = blend(
					bitmap.pixels[(lx + ly * bitmap.w) * 4 .. (lx + ly * bitmap.w) * 4 + 4],
					image.pixels[(lx + x + (ly + y) * image.w) * 4 .. (lx + x + (ly + y) * image.w) * 4 + 4],
					opacity);
		}
}

float[2] drawText(ref IFImage image, FT_Face face, string text, float x, float y, ubyte[4] color)
{
	bool kerning = FT_HAS_KERNING(face);
	uint glyphIndex, prev;
	foreach (c; text)
	{
		glyphIndex = FT_Get_Char_Index(face, cast(FT_ULong) c);
		if (kerning && prev && glyphIndex)
		{
			FT_Vector delta;
			FT_Get_Kerning(face, prev, glyphIndex, FT_Kerning_Mode.FT_KERNING_DEFAULT, &delta);
			x += delta.x / 64.0f;
			y += delta.y / 64.0f;
		}
		if (FT_Load_Glyph(face, glyphIndex, FT_LOAD_RENDER))
			continue;

		image.draw(face.glyph.bitmap, cast(int)(x + face.glyph.bitmap_left),
				cast(int)(y - face.glyph.bitmap_top), color);

		x += face.glyph.advance.x / 64.0f;
		y += face.glyph.advance.y / 64.0f;
		prev = glyphIndex;
	}
	return [x, y];
}

float[2] measureText(FT_Face face, string text)
{
	float x, y;
	x = y = 0;
	float h = 0;
	bool kerning = FT_HAS_KERNING(face);
	uint glyphIndex, prev;
	foreach (c; text)
	{
		glyphIndex = FT_Get_Char_Index(face, cast(FT_ULong) c);
		if (kerning && prev && glyphIndex)
		{
			FT_Vector delta;
			FT_Get_Kerning(face, prev, glyphIndex, FT_Kerning_Mode.FT_KERNING_DEFAULT, &delta);
			x += delta.x / 64.0f;
			y += delta.y / 64.0f;
		}
		if (FT_Load_Glyph(face, glyphIndex, FT_LOAD_COMPUTE_METRICS))
			continue;

		x += face.glyph.advance.x / 64.0f;
		y += face.glyph.advance.y / 64.0f;
		h = face.glyph.metrics.height > h ? face.glyph.metrics.height : h;
		prev = glyphIndex;
	}
	return [x, 0];
}

private ubyte[4] parseColor(char[3] hex)
{
	ubyte[4] ret;
	ret[3] = 0xFF;
	for (ubyte i = 0; i < 3; i++)
	{
		if (hex[i] >= '0' && hex[i] <= '9')
			ret[2 - i] = cast(ubyte)((hex[i] - '0') * 16);
		if (hex[i] >= 'A' && hex[i] <= 'F')
			ret[2 - i] = cast(ubyte)((hex[i] - 'A') * 16 + 160);
	}
	return ret;
}

void drawFormattedText(ref IFImage image, FT_Face regular, FT_Face boldFont,
		string text, float x, float y)
{
	import std.string : split;

	void updatePos(float[2] ret)
	{
		x = ret[0];
		y = ret[1];
	}

	if (!text.length)
		return;

	auto parts = text.split('$');
	ubyte[4] color;
	color[3] = 0xFF;
	bool bold;
	updatePos(image.drawText(regular, parts[0], x, y, color));
	if (parts.length > 1)
		foreach (part; parts[1 .. $])
		{
			if (!part.length)
				continue;
			if (part[0] == 'l')
				bold = true;
			else if (part[0] == 'r')
			{
				bold = false;
				color[] = 0;
				color[3] = 0xFF;
			}
			else if (part.length >= 3)
			{
				color = parseColor(part[0 .. 3]);
				updatePos(image.drawText(bold ? boldFont : regular, part[3 .. $], x, y, color));
				continue;
			}
			updatePos(image.drawText(bold ? boldFont : regular, part[1 .. $], x, y, color));
		}
}

abstract class Widget
{
	abstract int width(bool vertical) const;
	abstract int height(bool vertical) const;
	abstract bool hasHover() @property;
	abstract IFImage redraw(bool vertical, Bar bar, bool hovered);
	abstract void update(Bar bar);

	final void queueRedraw()
	{
		_queueRedraw = true;
	}

	final void clearRedraw()
	{
		_queueRedraw = false;
	}

	final bool requiresRedraw() @property const
	{
		return _queueRedraw;
	}

private:
	bool _queueRedraw;
}

interface IPropertyWatch
{
	void onPropertyChange(Window window, Atom property);
}

interface IMouseWatch
{
	void mouseDown(bool vertical, int x, int y, int button);
	void mouseUp(bool vertical, int x, int y, int button);
	void mouseMove(bool vertical, int x, int y);
}
