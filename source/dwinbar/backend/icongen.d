module dwinbar.backend.icongen;

import imageformats;

IFImage scaleImage(IFImage source, int targetWidth, int targetHeight)
{
	if (targetWidth == source.w && targetHeight == source.h || source.c != ColFmt.RGBA)
		return source;

	ubyte[] image = new ubyte[targetWidth * targetHeight * 4];

	float scaleX = source.w / cast(float) targetWidth;
	float scaleY = source.h / cast(float) targetHeight;

	if (targetWidth < source.w && targetHeight < source.h)
	{
		float remX = scaleX % 1;
		float remY = scaleY % 1;

		int scaleXi = cast(int) scaleX;
		int scaleYi = cast(int) scaleY;

		float overflowX = 0;
		float overflowY = 0;

		for (int y = 0; y < targetHeight; y++)
		{
			overflowY += remY;
			int countY = scaleYi;
			if (overflowY >= 1)
			{
				countY++;
				overflowY--;
			}

			overflowX = 0;
			for (int x = 0; x < targetWidth; x++)
			{
				overflowX += remX;
				int countX = scaleXi;
				if (overflowX >= 1)
				{
					countX++;
					overflowX--;
				}
				uint[4] sum;
				for (int oy = 0; oy < countY; oy++)
				{
					for (int ox = 0; ox < countX; ox++)
					{
						auto px = source.get(source.w, source.h, cast(int)(x * scaleX + ox),
								cast(int)(y * scaleY + oy));
						sum[0] += px[0];
						sum[1] += px[1];
						sum[2] += px[2];
						sum[3] += px[3];
					}
				}
				immutable sumCount = countX * countY;
				ubyte alpha = (sum[3] / sumCount) & 0xFF;
				sum[0] = ((sum[0] / sumCount) & 0xFF) * alpha / 256;
				sum[1] = ((sum[1] / sumCount) & 0xFF) * alpha / 256;
				sum[2] = ((sum[2] / sumCount) & 0xFF) * alpha / 256;
				image[(x + y * targetWidth) * 4 .. (x + y * targetWidth) * 4 + 4] = [sum[0] & 0xFF,
					sum[1] & 0xFF, sum[2] & 0xFF, sum[3] & 0xFF];
			}
		}
	}
	else
	{
		for (int y = 0; y < targetHeight; y++)
		{
			for (int x = 0; x < targetWidth; x++)
			{
				image[(x + y * targetWidth) * 4 .. (x + y * targetWidth) * 4 + 4] = interpolate2D(x * scaleX,
						y * scaleY, source, source.w, source.h);
			}
		}
	}
	IFImage ret;
	ret.c = ColFmt.RGBA;
	ret.w = targetWidth;
	ret.h = targetHeight;
	ret.pixels = image;
	return ret;
}

ulong[] scaleImage(int targetWidth, int targetHeight, in ulong[] source,
		int sourceWidth, int sourceHeight)
{
	if (targetWidth == sourceWidth && targetHeight == sourceHeight)
		return source.dup;

	ulong[] image = new ulong[targetWidth * targetHeight];

	float scaleX = sourceWidth / cast(float) targetWidth;
	float scaleY = sourceHeight / cast(float) targetHeight;

	if (targetWidth < sourceWidth && targetHeight < sourceHeight)
	{
		float remX = scaleX % 1;
		float remY = scaleY % 1;

		int scaleXi = cast(int) scaleX;
		int scaleYi = cast(int) scaleY;

		float overflowX = 0;
		float overflowY = 0;

		for (int y = 0; y < targetHeight; y++)
		{
			overflowY += remY;
			int countY = scaleYi;
			if (overflowY >= 1)
			{
				countY++;
				overflowY--;
			}

			overflowX = 0;
			for (int x = 0; x < targetWidth; x++)
			{
				overflowX += remX;
				int countX = scaleXi;
				if (overflowX >= 1)
				{
					countX++;
					overflowX--;
				}
				uint[4] sum;
				for (int oy = 0; oy < countY; oy++)
				{
					for (int ox = 0; ox < countX; ox++)
					{
						ulong px = source.get(sourceWidth, sourceHeight,
								cast(int)(x * scaleX + ox), cast(int)(y * scaleY + oy));
						sum[0] += px & 0xFF;
						sum[1] += (px >> 8) & 0xFF;
						sum[2] += (px >> 16) & 0xFF;
						sum[3] += (px >> 24) & 0xFF;
					}
				}
				immutable sumCount = countX * countY;
				ubyte alpha = (sum[3] / sumCount) & 0xFF;
				sum[0] = ((sum[0] / sumCount) & 0xFF) * alpha / 256;
				sum[1] = ((sum[1] / sumCount) & 0xFF) * alpha / 256;
				sum[2] = ((sum[2] / sumCount) & 0xFF) * alpha / 256;
				ulong result = sum[0] | (sum[1] << 8) | (sum[2] << 16) | (alpha << 24);
				image[x + y * targetWidth] = result;
			}
		}
	}
	else
	{
		for (int y = 0; y < targetHeight; y++)
		{
			for (int x = 0; x < targetWidth; x++)
			{
				image[x + y * targetWidth] = interpolate2D(x * scaleX, y * scaleY,
						source, sourceWidth, sourceHeight);
			}
		}
	}
	return image;
}

ulong interpolate2D(float targetX, float targetY, in ulong[] source,
		int sourceWidth, int sourceHeight)
{
	import std.math;

	ulong TL = source.get(sourceWidth, sourceHeight, cast(int) targetX, cast(int) targetY);
	ulong TR = source.get(sourceWidth, sourceHeight, cast(int) targetX + 1, cast(int) targetY);
	ulong BL = source.get(sourceWidth, sourceHeight, cast(int) targetX, cast(int) targetY + 1);

	float xd = targetX - cast(int) targetX;
	float yd = targetY - cast(int) targetY;

	return lerp(interpolate(TL, TR, xd), interpolate(TL, BL, yd), 0.5);
}

ulong get(in ulong[] source, int sourceWidth, int sourceHeight, int x, int y)
{
	if (x >= sourceWidth)
		x = sourceWidth - 1;
	if (y >= sourceHeight)
		y = sourceHeight - 1;
	if (x < 0)
		x = 0;
	if (y < 0)
		y = 0;
	return source[x + y * sourceWidth];
}

ulong interpolate(ulong a, ulong b, float amount)
{
	return lerp(a, b, amount);
}

ulong lerp(ulong a, ulong b, float amount)
{
	float iAmount = 1 - amount;
	ubyte aa = (a >> 24) & 0xFF;
	ubyte ba = (b >> 24) & 0xFF;
	ubyte c1 = cast(ubyte)((((a >> 0) & 0xFF) * aa / 256) * iAmount + (
			((b >> 0) & 0xFF) * ba / 256) * amount);
	ubyte c2 = cast(ubyte)((((a >> 8) & 0xFF) * aa / 256) * iAmount + (
			((b >> 8) & 0xFF) * ba / 256) * amount);
	ubyte c3 = cast(ubyte)((((a >> 16) & 0xFF) * aa / 256) * iAmount + (
			((b >> 16) & 0xFF) * ba / 256) * amount);
	ubyte c4 = cast(ubyte)(aa * iAmount + ba * amount);
	return (c1 << 0) | (c2 << 8) | (c3 << 16) | (c4 << 24);
}

ubyte[4] interpolate2D(float targetX, float targetY, in IFImage source,
		int sourceWidth, int sourceHeight)
{
	import std.math;

	auto TL = source.get(sourceWidth, sourceHeight, cast(int) targetX, cast(int) targetY);
	auto TR = source.get(sourceWidth, sourceHeight, cast(int) targetX + 1, cast(int) targetY);
	auto BL = source.get(sourceWidth, sourceHeight, cast(int) targetX, cast(int) targetY + 1);

	float xd = targetX - cast(int) targetX;
	float yd = targetY - cast(int) targetY;

	return lerp(interpolate(TL, TR, xd), interpolate(TL, BL, yd), 0.5);
}

ubyte[4] get(in IFImage source, int sourceWidth, int sourceHeight, int x, int y)
{
	if (x >= sourceWidth)
		x = sourceWidth - 1;
	if (y >= sourceHeight)
		y = sourceHeight - 1;
	if (x < 0)
		x = 0;
	if (y < 0)
		y = 0;
	return source.pixels[(x + y * sourceWidth) * 4 .. (x + y * sourceWidth) * 4 + 4][0 .. 4];
}

ubyte[4] interpolate(ubyte[4] a, ubyte[4] b, float amount)
{
	return lerp(a, b, amount);
}

ubyte[4] lerp(ubyte[4] a, ubyte[4] b, float amount)
{
	float iAmount = 1 - amount;
	ubyte aa = a[3];
	ubyte ba = b[3];
	ubyte c1 = cast(ubyte)((a[0] * aa / 256) * iAmount + (b[0] * ba / 256) * amount);
	ubyte c2 = cast(ubyte)((a[1] * aa / 256) * iAmount + (b[1] * ba / 256) * amount);
	ubyte c3 = cast(ubyte)((a[2] * aa / 256) * iAmount + (b[2] * ba / 256) * amount);
	ubyte c4 = cast(ubyte)(aa * iAmount + ba * amount);
	return [c1, c2, c3, c4];
}
