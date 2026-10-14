function frames = selectedFrames(ctx)
% Run selection is authoritative, including []/-1 meaning all raw frames.
% processData synthesizes ctx.frames from the existing ROI image length;
% using that cache length would truncate a new extraction on reruns.
frames = [];
if isfield(ctx, 'sel') && isstruct(ctx.sel) && isfield(ctx.sel, 'frames')
    frames = ctx.sel.frames;
elseif isfield(ctx, 'frames')
    frames = ctx.frames; % Legacy callers without a run selection.
end
end
