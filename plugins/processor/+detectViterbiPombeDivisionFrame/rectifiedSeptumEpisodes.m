function episodes=rectifiedSeptumEpisodes(frames,scores,positions,angles)
%RECTIFIEDSEPTUMEPISODES Experimental grouping, retaining isolated candidates.
% Angles are line directions in image coordinates, modulo 180 degrees.
% All thresholds are pilot settings, not calibrated biological decisions.
validateattributes(frames,{'numeric'},{'vector','integer','positive','increasing'});
frames=frames(:);scores=scores(:);positions=positions(:);angles=angles(:);
if any([numel(scores),numel(positions),numel(angles)]~=numel(frames))
    error('pombe:EpisodeSize','Frames, scores, positions and angles must have equal lengths.');
end
episodes=struct('frames',{},'onset',{},'peak',{},'peakScore',{},'confirmed',{});
indices=find(isfinite(scores)&scores>=1.5 & isfinite(positions)&isfinite(angles));
groups={};
for k=indices'
    joins=false;
    if ~isempty(groups)
        previous=groups{end}(end);
        angleDistance=abs(mod(angles(k)-angles(previous)+90,180)-90);
        joins=frames(k)-frames(previous)==1 && ...
            abs(positions(k)-positions(previous))<=.15 && angleDistance<=15;
    end
    if joins,groups{end}(end+1)=k;else,groups{end+1}=k;end %#ok<AGROW>
end
for i=1:numel(groups)
    group=groups{i};[peak,k]=max(scores(group));
    episodes(end+1)=struct('frames',frames(group)', ...
        'onset',frames(group(1)),'peak',frames(group(k)), ...
        'peakScore',peak,'confirmed',numel(group)>=2); %#ok<AGROW>
end
end
