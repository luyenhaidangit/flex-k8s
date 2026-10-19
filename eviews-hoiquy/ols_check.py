import numpy as np
from scipy import stats
Y=np.array([40,44,46,48,52,58,60,68,74,90.]);X=np.array([8,9,9,10,11,12,12,13,14,15.]);Z=np.array([5,5,4.5,4.5,4,4,3.5,3.5,3,2.5])
n=10;k=3;df=n-k
A=np.c_[np.ones(n),X,Z];inv=np.linalg.inv(A.T@A);b=inv@A.T@Y;e=Y-A@b
rss=e@e;tss=((Y-Y.mean())**2).sum();s2=rss/df;se=np.sqrt(s2*np.diag(inv))
t=b/se;p=2*stats.t.sf(abs(t),df);tc=stats.t.ppf(.975,df)
print("b",b);print("se",se);print("t",t);print("p",p);print("CI",b-tc*se,b+tc*se)
R2=1-rss/tss;adj=1-(1-R2)*(n-1)/df;F=(R2/(k-1))/((1-R2)/df);print("R2",R2,adj,"F",F,stats.f.sf(F,k-1,df),"rss",rss,"s",np.sqrt(s2),"tc",tc)
dw=(np.diff(e)**2).sum()/rss;print("DW",dw)
print("loglik",-n/2*(1+np.log(2*np.pi)+np.log(rss/n)),"AIC",2*k/n+1+np.log(2*np.pi)+np.log(rss/n))
x0=np.array([1,15,6]);y0=x0@b;v=x0@inv@x0
for nm,vv in(("mean",s2*v),("indiv",s2*(1+v))):
    sd=np.sqrt(vv);print(nm,y0,sd,y0-tc*sd,y0+tc*sd)
# partial: t test beta2>0? beta3<0 ; corr X,Z
print("corr",np.corrcoef(X,Z)[0,1])
