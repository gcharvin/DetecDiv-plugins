function [score, position, info] = scoreRectifiedSeptum(raw, mask)
%SCORERECTIFIEDSEPTUM Experimental conventional detector; not a pipeline default.
% Rectify a smooth, single-valued cell centreline, retain transverse support,
% and require the same stripe to survive two smoothing scales. Near-isotropic
% masks use image-based orientation search rather than an arbitrary PCA axis.
validateattributes(raw,{'numeric'},{'real','2d','finite'});
validateattributes(mask,{'numeric','logical'},{'real','2d','finite','size',size(raw)});
mask=mask>0;score=NaN;position=NaN;
info=struct('axisMode','unavailable','axisConfidence',NaN,'coverage',NaN, ...
    'angle',NaN,'flankOffset',NaN,'noiseScale',NaN,'lineEndpoints',nan(2), ...
    'centerline',[],'rectified',[],'profile',[],'profileContrast',[], ...
    'candidateScores',[],'selectedRow',NaN,'searchOrientation',NaN);
[y,x]=find(mask);if numel(x)<30,return;end
coords=[x y];center=mean(coords,1);[~,S,V]=svd(coords-center,'econ');
e=diag(S).^2;confidence=(e(1)-e(2))/max(sum(e),eps);
u=V(:,1)';if u(1)<0 || (abs(u(1))<eps && u(2)<0),u=-u;end
orientations=atan2d(u(2),u(1));mode='curved_axis';
if confidence<.2,orientations=0:15:165;mode='orientation_search';end
raw=double(raw);distance=bwdist(~mask);interior=distance>=2;
images={imgaussfilt(raw,.8,'Padding','replicate'), ...
    imgaussfilt(raw,1.5,'Padding','replicate')};
noise=zeros(1,2);
for scale=1:2
    residual=images{scale}-imgaussfilt(images{scale},3,'Padding','replicate');
    values=residual(interior);if isempty(values),return;end
    range=max(images{scale}(mask))-min(images{scale}(mask));
    noise(scale)=max(1.4826*median(abs(values-median(values))), ...
        max(range*1e-6,eps(max(abs(images{scale}(mask))))));
end
score=0;info.axisMode=mode;info.axisConfidence=confidence;info.noiseScale=noise;
for orientation=orientations
    u=[cosd(orientation) sind(orientation)];n=[-u(2) u(1)];
    projected=(coords-center)*u';transverse=(coords-center)*n';
    s=(ceil(min(projected)):floor(max(projected)))';
    t=floor(min(transverse)):ceil(max(transverse));
    if numel(s)<12 || numel(t)<5,continue;end
    X=center(1)+s*u(1)+t*n(1);Y=center(2)+s*u(2)+t*n(2);
    inside=interp2(double(mask),X,Y,'nearest',0)>.5;
    mid=nan(size(s));
    for k=1:numel(s)
        occupied=t(inside(k,:));
        if ~isempty(occupied),mid(k)=(min(occupied)+max(occupied))/2;end
    end
    good=isfinite(mid);if nnz(good)<12,continue;end
    mid=interp1(s(good),mid(good),s,'linear','extrap');
    width=median(sum(inside,2));
    if strcmp(mode,'curved_axis')
        mid=smoothdata(mid,'gaussian',max(5,2*floor(width/2)+1));
    else
        mid(:)=0;
    end
    centers=center+s*u+mid*n;
    tangent=u+gradient(mid)*n;tangent=tangent./vecnorm(tangent,2,2);
    normal=[-tangent(:,2) tangent(:,1)];
    ray=-ceil(max(numel(t),width)):ceil(max(numel(t),width));
    rx=centers(:,1)+normal(:,1)*ray;ry=centers(:,2)+normal(:,2)*ray;
    safe=interp2(distance,rx,ry,'linear',0)>=1.5;
    left=nan(size(s));right=left;zero=find(ray==0);
    for k=1:numel(s)
        if ~safe(k,zero),continue;end
        a=zero;b=zero;
        while a>1 && safe(k,a-1),a=a-1;end
        while b<numel(ray) && safe(k,b+1),b=b+1;end
        left(k)=ray(a);right(k)=ray(b);
    end
    eta=linspace(0,1,41);r=left+(right-left).*eta;
    gx=centers(:,1)+r.*normal(:,1);gy=centers(:,2)+r.*normal(:,2);
    strip=cellfun(@(im)interp2(im,gx,gy,'linear',NaN),images,'UniformOutput',false);
    if isempty(info.centerline)
        info.centerline=centers;info.rectified=strip{1};
        info.profile=median(strip{1},2,'omitnan');
        info.searchOrientation=orientation;
    end
    baseValid=(right-left)>=6 & isfinite(left);
    baseValid=baseValid & s>=min(s)+.2*rangeOf(s) & s<=max(s)-.2*rangeOf(s);
    bestRows=zeros(size(s));bestContrast=nan(size(s));
    [col,row]=meshgrid(1:numel(eta),1:numel(s));
    for angle=-15:5:15
        tilted=row+(r-mean(r,2))*tand(angle);
        for offset=[3 5 7]
            response=inf(size(strip{1}));
            for scale=1:2
                image=strip{scale};
                middle=interp2(image,col,tilted,'linear',NaN);
                a=interp2(image,col,tilted-offset,'linear',NaN);
                b=interp2(image,col,tilted+offset,'linear',NaN);
                response=min(response,min(a-middle,b-middle)/noise(scale));
            end
            valid=isfinite(response);
            coverage=sum(valid & response>.75,2)/numel(eta);
            sectors=[median(response(:,1:13),2,'omitnan'), ...
                median(response(:,14:28),2,'omitnan'), ...
                median(response(:,29:41),2,'omitnan')];
            contrast=prctile(response,25,2);
            scores=max(0,contrast).*coverage;
            scores(~baseValid | sum(valid,2)<.9*numel(eta) | ...
                coverage<.8 | min(sectors,[],2)<.75)=0;
            scores(~isfinite(scores))=0;
            improved=scores>bestRows;bestRows(improved)=scores(improved);
            bestContrast(improved)=contrast(improved);
            [candidate,k]=max(scores);
            if candidate>score
                score=candidate;position=(s(k)-min(s))/rangeOf(s);
                info.coverage=coverage(k);info.angle=mod(atan2d(normal(k,2),normal(k,1))-angle,180);
                info.flankOffset=offset;info.noiseScale=noise;
                % Endpoints follow the actual tilted section in image space.
                rr=tilted(k,[1 end]);
                info.lineEndpoints=[interp2(gx,[1 numel(eta)],rr,'linear',NaN)', ...
                    interp2(gy,[1 numel(eta)],rr,'linear',NaN)'];
                info.centerline=centers;info.rectified=strip{1};
                info.profile=median(strip{1},2,'omitnan');info.selectedRow=k;
                info.searchOrientation=orientation;
            end
        end
    end
    if isfinite(info.searchOrientation) && info.searchOrientation==orientation
        info.candidateScores=bestRows;info.profileContrast=bestContrast;
    end
end
end

function value=rangeOf(x)
value=max(max(x)-min(x),eps);
end
