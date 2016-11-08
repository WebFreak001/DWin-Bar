module dwinbar.backend.icongen;

import dwinbar.widgets.widget;

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
