function drawText(text, win, yoffset, color, textsize)

[width, height] = Screen('WindowSize', win);
Screen('TextSize', win, textsize);
[textbox, textbox2] = Screen('TextBounds', win, text);
Screen('DrawText', win, text, (width-textbox(3))/2, (height-textbox(4))/2 + yoffset, color);

return;
