function q=scoreFocusQuality(raw,p)
%SCOREFOCUSQUALITY Relative fine detail and trap-edge strength, without masks.
% Full supplied movie defines the reference, even for a sparse frame request.
[H,W,~,T]=size(raw);
regions=value(p,'focusRegions',[.20 .23 .66 .18;.20 .70 .66 .15]);
validateattributes(regions,{'numeric'},{'2d','ncols',4,'finite','nonnegative'});
if isempty(regions)||any(regions(:,3:4)<=0,'all')||any(regions(:,1:2)+regions(:,3:4)>1,'all')
    error('pombe:FocusRegions','Focus regions must be normalized [x y width height] rectangles inside the ROI.');
end
dt=value(p,'focusDetailRatioThreshold',.5);et=value(p,'focusEdgeRatioThreshold',.92);
minRef=value(p,'focusMinReferenceFrames',5);
validateattributes(dt,{'numeric'},{'scalar','>',0,'<',1,'finite'});
validateattributes(et,{'numeric'},{'scalar','>',0,'<=',1,'finite'});
validateattributes(minRef,{'numeric'},{'scalar','integer','>=',3,'finite'});
[xx,yy]=meshgrid((1:W)/W,(1:H)/H);region=false(H,W);
for k=1:size(regions,1)
    b=regions(k,:);region=region|(xx>b(1)&xx<b(1)+b(3)&yy>b(2)&yy<b(2)+b(4));
end
if nnz(region)<16,error('pombe:FocusRegionTooSmall','Focus regions contain fewer than 16 pixels.');end
detail=nan(T,1);edge=detail;contrast=detail;invalid=false(T,1);
for f=1:T
    a=double(raw(:,:,1,f));
    if any(~isfinite(a),'all'),invalid(f)=true;continue;end
    bounds=prctile(a(:),[1 99]);contrast(f)=bounds(2)-bounds(1);
    if contrast(f)<=0,invalid(f)=true;continue;end
    z=max(0,min(1,(a-bounds(1))/contrast(f)));
    lap=imfilter(z,[0 1 0;1 -4 1;0 1 0],'symmetric');detail(f)=var(lap(region),1);
    sm=imgaussfilt(z,1,'FilterSize',9,'Padding','symmetric');
    [gx,gy]=gradient(sm);g=hypot(gx,gy);edge(f)=prctile(g(region),90);
end
reference=isfinite(detail)&detail>0&isfinite(edge)&edge>0&~invalid;
dr=NaN;er=NaN;detailRatio=nan(T,1);edgeRatio=detailRatio;status='insufficient_reference';
if nnz(reference)>=minRef
    dr=median(detail(reference));er=median(edge(reference));
    detailRatio=detail/dr;edgeRatio=edge/er;status='relative_reference_ready';
end
rejected=invalid|(detailRatio<dt&edgeRatio<et);
reason=zeros(T,1,'uint8');reason(invalid)=1;reason(rejected&~invalid)=2;
q=struct('method','relative_trap_detail_and_edges_v1','status',status, ...
    'referenceFrames',find(reference)','referenceFrameCount',nnz(reference), ...
    'regions',regions,'detailReference',dr,'edgeReference',er, ...
    'detailRatioThreshold',dt,'edgeRatioThreshold',et,'minReferenceFrames',minRef, ...
    'detail',detail,'edge',edge,'contrastP01P99',contrast, ...
    'detailRatio',detailRatio,'edgeRatio',edgeRatio,'rejected',rejected,'reason',reason, ...
    'reasonLegend',{{'0 accepted or insufficient relative reference', ...
    '1 nonfinite or zero contrast','2 joint loss of detail and edge strength'}}, ...
    'limitations','Relative within-movie QC; cannot identify a uniformly defocused movie. Thresholds require acquisition validation.');
end
function v=value(p,key,fallback)
v=fallback;if isfield(p,key)&&~isempty(p.(key)),v=p.(key);end
end
